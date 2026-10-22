require 'net/http'

module Comrade
  # The reply loop: persists the user message, streams the model's answer
  # from any OpenAI-compatible chat-completions endpoint, and persists the
  # assistant message on clean completion. Yields structured events —
  # {type: 'delta'} text, {type: 'tool'} activity — the caller owns
  # transport. When the model emits tool_calls, the loop pauses streaming,
  # executes the tools, persists the exchange, and resumes with the results
  # in context; the tool round trip is invisible to the wire except as
  # tool events between text.
  # The system prompt is config, never a row: the shipped voice lives in
  # config/comrade_prompt.md, and a personal comrade_prompt.custom.md
  # (gitignored) overrides it wholesale.
  class Reply
    DEFAULT_PROMPT = Rails.root.join('config/comrade_prompt.md')
    CUSTOM_PROMPT = Rails.root.join('config/comrade_prompt.custom.md')

    # The endpoint is unreachable or misconfigured.
    class UnavailableError < StandardError; end

    MAX_TOOL_ROUNDS = 3

    # Tool definitions in OpenAI's schema — the model names these in
    # tool_calls; the registry below maps names to implementations.
    DEFINITIONS = [
      {
        type: 'function',
        function: {
          name: 'web_search',
          description: 'Search the web. Use when you lack the facts to answer.',
          parameters: {
            type: 'object',
            properties: { query: { type: 'string', description: 'The search query' } },
            required: ['query'],
          },
        },
      },
      {
        type: 'function',
        function: {
          name: 'fetch_page',
          description: 'Fetch a URL and return its full text content.',
          parameters: {
            type: 'object',
            properties: { url: { type: 'string', description: 'The URL to fetch' } },
            required: ['url'],
          },
        },
      },
    ].freeze

    def self.call(conversation:, content:)
      reply = new(conversation: conversation, content: content)
      reply.append_message(role: 'user', content: content)
      reply.enumerator
    end

    def initialize(conversation:, content:)
      @conversation = conversation
      @content = content
    end

    # The user message is persisted eagerly (so validation errors surface
    # as 422 before any streaming starts); the assistant message persists
    # when the enumerator is fully consumed.
    def enumerator
      Enumerator.new { |yielder| stream_into(yielder) }
    end

    def append_message(role:, content:, **fields)
      @conversation.messages.create!(role: role, content: content, **fields)
    end

    private

    def stream_into(yielder)
      citations = []
      MAX_TOOL_ROUNDS.times do
        frame = stream_pass(yielder)
        return persist_answer(frame[:content], citations, yielder) if frame[:tool_calls].empty?

        citations += run_tool_round(frame, yielder)
      end
      # The model kept calling tools past the cap — answer with what exists.
      append_message(role: 'assistant', content: 'I hit the tool-use limit before I could finish.')
    end

    def run_tool_round(frame, yielder)
      tool_calls = frame[:tool_calls].values
      persist_tool_calls(frame[:content], tool_calls)
      tool_calls.flat_map { |tool_call| run_tool_call(tool_call, yielder) }
    end

    def run_tool_call(tool_call, yielder)
      arguments = JSON.parse(tool_call[:arguments])
      result, found = execute_tool(tool_call[:name], arguments, yielder)
      append_message(role: 'tool',
        content: result,
        tool_name: tool_call[:name],
        tool_payload: { arguments: arguments, tool_call_id: tool_call[:id] },)
      found
    end

    # One streaming request/response pass. Text deltas flow out as events;
    # tool_call fragments accumulate until the stream ends, so the whole
    # frame lands complete. Returns { content:, tool_calls: } (indexed).
    def stream_pass(yielder)
      content = +''
      tool_calls = Hash.new { |hash, index| hash[index] = { id: nil, name: +'', arguments: +'' } }
      each_frame { |delta| absorb_delta(delta, content, tool_calls, yielder) }
      { content: content, tool_calls: tool_calls }
    end

    def absorb_delta(delta, content, tool_calls, yielder)
      text = delta['content']
      calls = delta['tool_calls']
      return unless text || calls

      absorb_text(text, content, yielder) if text
      Array(calls).each { |fragment| absorb_tool_call(tool_calls, fragment) }
    end

    def absorb_text(text, content, yielder)
      content << text
      yielder << { type: 'delta', text: text }
    end

    def absorb_tool_call(tool_calls, fragment)
      partial = tool_calls[fragment['index']]
      partial[:id] = fragment['id'] if fragment['id']
      partial[:name] << fragment.dig('function', 'name').to_s
      partial[:arguments] << fragment.dig('function', 'arguments').to_s
    end

    # The assistant frame that requested tools persists with null content
    # when it emitted none — the transcript rebuilds its tool_calls from
    # tool_payload, keeping the wire conversation valid for later turns.
    def persist_tool_calls(content, tool_calls)
      append_message(role: 'assistant',
        content: content.presence,
        tool_payload: { tool_calls: tool_calls.map { |call| tool_call_frame(call) } },)
    end

    def tool_call_frame(call)
      { id: call[:id],
        type: 'function',
        function: { name: call[:name], arguments: call[:arguments] }, }
    end

    def execute_tool(name, arguments, yielder)
      yielder << { type: 'tool', name: name }.merge(arguments)
      dispatch_tool(name, arguments)
    rescue JSON::ParserError
      ['Invalid tool arguments', []]
    end

    def dispatch_tool(name, arguments)
      case name
      when 'web_search' then search_with_citations(arguments['query'])
      when 'fetch_page' then fetch_with_citations(arguments['url'])
      else ["Unknown tool: #{ name }", []]
      end
    end

    def search_with_citations(query)
      results = Tools::WebSearch.call(query: query)
      citations = results.is_a?(Array) ? results.map { |result| { title: result['title'], url: result['url'] } } : []
      [results.to_json, citations]
    end

    def fetch_with_citations(url)
      content = Tools::FetchPage.call(url: url)
      citations = content.start_with?('Fetch ') ? [] : [title: url, url: url]
      [content, citations]
    end

    def persist_answer(content, citations, yielder)
      citations = citations.uniq { |citation| citation[:url] }.presence
      append_message(role: 'assistant', content: content, citations: citations)
      yielder << { type: 'citations', citations: citations || [] } if citations
    end

    # read_body yields raw TCP chunks whose boundaries ignore SSE event
    # boundaries, so complete lines are buffered out here. The parser
    # yields full delta objects — content and tool_call fragments both —
    # and drops role-only frames and [DONE].
    def each_frame
      buffer = +''
      stream_chunks do |chunk|
        buffer << chunk
        while (line = buffer.slice(/\A[^\n]*\n/))
          buffer.slice!(0, line.length)
          delta = delta_for(line)
          yield delta if delta
        end
      end
    end

    def delta_for(line)
      payload = line.strip[/\Adata: ?(.*)\z/, 1]
      return if payload.blank? || payload == '[DONE]'

      JSON.parse(payload).dig('choices', 0, 'delta')
    end

    def stream_chunks(&block)
      http = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https')
      http.request(post_request) do |response|
        ensure_success(response)
        response.read_body(&block)
      end
    rescue Errno::ECONNREFUSED, SocketError, Net::OpenTimeout => error
      raise UnavailableError, "LLM endpoint unreachable: #{ error.message }"
    ensure
      http&.finish
    end

    def post_request
      request = Net::HTTP::Post.new(uri.request_uri, headers)
      request.body = payload.to_json
      request
    end

    def ensure_success(response)
      return if response.is_a?(Net::HTTPSuccess)

      raise UnavailableError, "LLM endpoint returned HTTP #{ response.code }"
    end

    def uri
      @uri ||= URI.parse("#{ base_url.chomp('/') }/chat/completions")
    end

    def base_url
      ENV.fetch('COMRADE_LLM_BASE_URL') { raise UnavailableError, 'COMRADE_LLM_BASE_URL is not set' }
    end

    def headers
      # Header names are strings on the wire — the StringHashKeys cop is
      # guarding keyword-argument hashes, which this isn't.
      # rubocop:disable Style/StringHashKeys
      { 'Content-Type' => 'application/json' }.tap do |header|
        header['Authorization'] = "Bearer #{ ENV['COMRADE_LLM_API_KEY'] }" if ENV['COMRADE_LLM_API_KEY']
      end
      # rubocop:enable Style/StringHashKeys
    end

    def payload
      {
        model: ENV.fetch('COMRADE_LLM_MODEL'),
        messages: [role: 'system', content: prompt] + @conversation.to_transcript,
        tools: DEFINITIONS,
        stream: true,
      }
    end

    def prompt
      path = CUSTOM_PROMPT.exist? ? CUSTOM_PROMPT : DEFAULT_PROMPT
      raise UnavailableError, "System prompt missing at #{ path }" unless path.exist?

      path.read
    end
  end
end
