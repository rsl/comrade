require 'net/http'

module Comrade
  # The reply loop: persists the user message, streams the model's answer
  # from any OpenAI-compatible chat-completions endpoint, and persists the
  # assistant message on clean completion. Yields structured events —
  # {type: 'delta'} text, {type: 'tool'} activity, {type: 'error'} upstream
  # failure — the caller owns transport. When the model emits tool_calls, the
  # loop pauses streaming,
  # executes the tools, persists the exchange, and resumes with the results
  # in context; the tool round trip is invisible to the wire except as
  # tool events between text.
  # The system prompt is config, never a row: the shipped voice lives in
  # config/comrade_prompt.md, and a personal comrade_prompt.custom.md
  # (gitignored) overrides it wholesale.
  class Reply
    DEFAULT_PROMPT = Rails.root.join('config/comrade_prompt.md')
    CUSTOM_PROMPT = Rails.root.join('config/comrade_prompt.custom.md')

    MAX_TOOL_ROUNDS = 3
    # Net::HTTP's 60s default is an IDLE timeout, not a total one — but a
    # busy model server queues requests without sending a byte, so the
    # default reads "queued" as "dead" and fails a reply that would have
    # succeeded. Give the queue room.
    TIMEOUTS = { read_timeout: 300, open_timeout: 30 }.freeze

    # The cap pass gets no tools; left to its own devices the model then
    # emits its next search as fake tool-call text in the answer. This
    # appended system line is the actual lever.
    FINAL_ANSWER_DIRECTIVE = 'You have no tools for this reply. Write your final answer NOW, in words, ' \
                             'from what the earlier searches gathered. Never write tool calls as text.'

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

    def self.call(conversation:, content:, interrupted: nil)
      reply = new(conversation: conversation, content: content)
      persist_lead_in(reply, conversation, interrupted)
      reply.append_message(role: 'user', content: content)
      reply.enumerator
    end

    # A retried reply: the user message persisted with the failed attempt,
    # so only the lead-in (steered partial, resurrection) applies.
    def self.call_retry(conversation:, content:, interrupted: nil)
      reply = new(conversation: conversation, content: content)
      persist_lead_in(reply, conversation, interrupted)
      reply.enumerator
    end

    def self.persist_lead_in(reply, conversation, interrupted)
      # A steered reply carries the partial answer the interrupted stream
      # had already shown; it persists first so the model sees its own
      # cut-off sentence followed by the new message.
      reply.append_message(role: 'assistant', content: interrupted) if interrupted.present?
      conversation.resurrect if conversation.archived?
    end

    def initialize(conversation:, content:)
      @conversation = conversation
      @content = content
      # The stream sink is attached when the enumerator starts.
      @yielder = nil
    end

    # The user message is persisted eagerly (so validation errors surface
    # as 422 before any streaming starts); the assistant message persists
    # when the enumerator is fully consumed.
    def enumerator
      Enumerator.new do |yielder|
        @yielder = yielder
        stream_into
      end
    end

    def append_message(role:, content:, **fields)
      @conversation.messages.create!(role: role, content: content, **fields)
    end

    private

    # The stream sink: everything the answer pass emits crosses this. Nil
    # until the enumerator starts — the generator runs only inside it.
    attr_reader :yielder

    def stream_into
      citations = []
      MAX_TOOL_ROUNDS.times do
        frame = stream_pass
        return persist_answer(frame[:content], citations) if frame[:tool_calls].empty?

        citations.concat(run_tool_round(frame, citations.size))
      end
      final_answer(citations)
    end

    # Cap reached: one last pass with no tools on offer — the model must
    # answer from what the rounds gathered instead of dead-ending. The
    # appended system line is the actual lever: left to its own devices
    # the model emits its next search as fake tool-call text in the answer.
    def final_answer(citations)
      frame = stream_pass(tool_definitions: [], final_instruction: FINAL_ANSWER_DIRECTIVE)
      persist_answer(frame[:content], citations)
    end

    # The round starts numbering sources at offset and advances it by each
    # result set the round yields — parallel searches and fetches in one
    # frame number continuously.
    def run_tool_round(frame, offset)
      tool_calls = frame[:tool_calls].values
      persist_tool_calls(frame[:content], tool_calls)
      run_numbered_tool_calls(tool_calls, offset)
    end

    def run_numbered_tool_calls(tool_calls, offset)
      number = offset
      tool_calls.flat_map do |tool_call|
        found = run_tool_call(tool_call, number)
        number += found.size
        found
      end
    end

    def run_tool_call(tool_call, offset)
      arguments = JSON.parse(tool_call[:arguments])
      result, found = execute_tool(tool_call[:name], arguments, offset)
      append_message(role: 'tool',
        content: result,
        tool_name: tool_call[:name],
        tool_payload: { arguments: arguments, tool_call_id: tool_call[:id] },)
      found
    end

    # One streaming request/response pass. Text deltas flow out as events;
    # tool_call fragments accumulate until the stream ends, so the whole
    # frame lands complete. Returns { content:, tool_calls: } (indexed).
    def stream_pass(tool_definitions: DEFINITIONS, final_instruction: nil)
      content = +''
      tool_calls = Hash.new { |hash, index| hash[index] = { id: nil, name: +'', arguments: +'' } }
      each_frame(payload(tool_definitions: tool_definitions, final_instruction: final_instruction)) do |delta|
        absorb_delta(delta, content, tool_calls)
      end
      { content: content, tool_calls: tool_calls }
    end

    def absorb_delta(delta, content, tool_calls)
      text = delta['content']
      calls = delta['tool_calls']
      return unless text || calls

      absorb_text(text, content) if text
      Array(calls).each { |fragment| absorb_tool_call(tool_calls, fragment) }
    end

    def absorb_text(text, content)
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

    def execute_tool(name, arguments, offset)
      yielder << { type: 'tool', name: name }.merge(arguments)
      dispatch_tool(name, arguments, offset)
    rescue JSON::ParserError
      ['Invalid tool arguments', []]
    end

    def dispatch_tool(name, arguments, offset)
      case name
      when 'web_search' then search_results(arguments['query'], offset)
      when 'fetch_page' then fetch_content(arguments['url'], offset)
      else ["Unknown tool: #{ name }", []]
      end
    end

    # The model cites by [n], so it needs the real titles and urls —
    # sources stripped of addresses are exactly what got confabulated.
    # Numbering continues across rounds so the footer's [n] matches the
    # canonical citations list the renderer resolves against.
    def search_results(query, offset)
      results = Tools::WebSearch.call(query: query)
      return ['(no results)', []] unless results.is_a?(Array)

      shown = results.each_with_index.map do |result, index|
        "[#{ offset + index + 1 }] #{ result['title'] } — #{ result['url'] }\n#{ result['content'] }"
      end
      [shown.join("\n\n"),
       results.map { |result| { title: result['title'], url: result['url'] } },]
    end

    def fetch_content(url, offset)
      content = Tools::FetchPage.call(url: url)
      if content.start_with?('Fetch ', 'No content')
        failed = 'No content could be extracted from that page — do not retry it or similar URLs;'
        return ["#{ failed } work from the search results or answer from what you have.", []]
      end

      ["[#{ offset + 1 }] #{ url }\n\n#{ content }", [title: url, url: url]]
    end

    def persist_answer(content, citations)
      citations = citations.uniq { |citation| citation[:url] }.presence
      append_message(role: 'assistant', content: content, citations: citations)
      yielder << { type: 'citations', citations: citations || [] } if citations
    end

    # read_body yields raw TCP chunks whose boundaries ignore SSE event
    # boundaries, so complete lines are buffered out here. The parser
    # yields full delta objects — content and tool_call fragments both —
    # and drops role-only frames and [DONE].
    def each_frame(request_body)
      buffer = +''
      stream_chunks(request_body) do |chunk|
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

    # Net::HTTP's 60s default is an IDLE timeout, not a total one — but a busy
    # model server queues requests without sending a byte, so the default
    # reads "queued" as "dead" and fails a reply that would have succeeded.
    # Give the queue room.
    def stream_chunks(request_body, &block)
      http = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', **TIMEOUTS)
      http.request(post_request(request_body)) do |response|
        ensure_success(response)
        response.read_body(&block)
      end
    rescue Errno::ECONNREFUSED,
           SocketError,
           Net::OpenTimeout,
           Net::ReadTimeout,
           Errno::ECONNRESET,
           Errno::EPIPE,
           EOFError => error
      # ReadTimeout is the common one: a slow endpoint (cold model load,
      # long prefill) stays silent past Net::HTTP's 60s read timeout.
      raise UpstreamError, "LLM endpoint unreachable: #{ error.message }"
    ensure
      http&.finish
    end

    def post_request(request_body)
      request = Net::HTTP::Post.new(uri.request_uri, headers)
      request.body = request_body.to_json
      request
    end

    def ensure_success(response)
      return if response.is_a?(Net::HTTPSuccess)

      raise UpstreamError, "LLM endpoint returned HTTP #{ response.code }"
    end

    def uri
      @uri ||= URI.parse("#{ turn_lane.base_url.chomp('/') }/chat/completions")
    end

    def headers
      # Header names are strings on the wire — the StringHashKeys cop is
      # guarding keyword-argument hashes, which this isn't.
      # rubocop:disable-next Style/StringHashKeys
      { 'Content-Type' => 'application/json' }.tap do |header|
        header['Authorization'] = "Bearer #{ turn_lane.api_key }" if turn_lane.api_key
      end
    end

    def payload(tool_definitions: DEFINITIONS, final_instruction: nil)
      messages = [{ role: 'system', content: prompt }, prefs_message].compact
      messages.concat(@conversation.to_transcript)
      messages << { role: 'system', content: final_instruction } if final_instruction
      request = {
        model: turn_lane.model,
        messages: messages,
        tools: tool_definitions,
        stream: true,
        max_tokens: 8192,
      }
      request[:reasoning_effort] = turn_lane.effort if turn_lane.effort
      request
    end

    # Prefs ride as a second system message layered after the base prompt —
    # one injection point forever; new prefs are new jsonb keys, no
    # migrations. Values are directive lines the reader authored (Party
    # Line, or a confirmed nudge); keys are addresses. Like the system
    # prompt, prefs are config, never a row. The commune has no row, so it
    # always gets the factory voice.
    def prefs_message
      prefs = @conversation.comrade&.prefs
      lines = prefs&.values&.filter_map(&:presence)
      return if lines.blank?

      { role: 'system', content: "How this reader wants answers — apply as written:\n#{ lines.join("\n") }" }
    end

    def prompt
      path = CUSTOM_PROMPT.exist? ? CUSTOM_PROMPT : DEFAULT_PROMPT
      raise UpstreamError, "System prompt missing at #{ path }" unless path.exist?

      path.read
    end

    # The endpoint a turn rides, decided once per turn — TurnLane below
    # owns the how. Ordinary turns ride the fast lane
    # (COMRADE_LLM_FAST_BASE_URL/_API_KEY/_MODEL — instant chat and
    # search); a turn that invokes depth — the depth-words the prompt
    # file names, or a pasted link ("read this one") — rides the slow
    # lane (COMRADE_LLM_SLOW_*), the deliberate endpoint. The fleet
    # starts small: with no fast lane configured, every turn rides the
    # legacy COMRADE_LLM_* triple exactly as lane-less comrade did; with
    # no slow lane, depth invocation stays on the same endpoint; a lane
    # without its own API key shares the legacy one. Turn lanes memoize
    # per reply, not per process.

    def turn_lane
      @turn_lane ||= TurnLane.build(@content)
    end

    class TurnLane
      # Depth-mode invocation words, per config/comrade_prompt.md ("depth
      # is a mode the reader invokes with 'go deeper', 'find the study',
      # and words like that") — that file is the source of truth; keep
      # these mirroring it.
      DEPTH_TRIGGERS =
        /\b(go deeper|dive deeper|dig into|dig deeper|find the study|pull the study|walk me through|in detail)\b/i

      # A pasted link: "read this one" is an explicit pointer to a source.
      LINK = %r{\bhttps?://}i

      attr_reader :base_url, :model, :api_key, :effort

      def self.build(content)
        new(content)
      end

      def initialize(content)
        @content = content
        kind = ENV['COMRADE_LLM_FAST_BASE_URL'] ? default_kind : 'legacy'
        build_lane(kind)
        @effort = method("#{ kind }_effort").call
      end

      def default_kind
        invoked? && ENV['COMRADE_LLM_SLOW_BASE_URL'] ? 'slow' : 'fast'
      end

      private

      def build_lane(which)
        @base_url = required_env(which, 'BASE_URL')
        @model = required_env(which, 'MODEL')
        @api_key = ENV[api_key_env(which)] || ENV['COMRADE_LLM_API_KEY']
      end

      # The legacy lane rides the unsuffixed names — the original
      # COMRADE_LLM_* triple, which is the degrade contract: one triple
      # configured, no fast lane, everything exactly as lane-less comrade
      # ran it.
      def env_name(which, suffix)
        return "COMRADE_LLM_#{ suffix }" if which == 'legacy'

        "COMRADE_LLM_#{ which.upcase }_#{ suffix }"
      end

      def api_key_env(which)
        env_name(which, 'API_KEY')
      end

      def required_env(which, suffix)
        key = env_name(which, suffix)
        value = ENV[key]
        return value if value.present?

        raise UpstreamError, "#{ key } is not set"
      end

      def invoked?
        @content.match?(DEPTH_TRIGGERS) || @content.match?(LINK)
      end

      def words?
        @content.match?(DEPTH_TRIGGERS)
      end

      # Depth mode: the reader invoked it in words, so think hard; a
      # pasted link is explicit but skips the pre-deliberation budget.
      # COMRADE_LLM_SLOW_EFFORT: 'adaptive' (also unset) encodes exactly
      # that word/link split; 'low'/'high' pin it; anything unknown fails
      # loudly — misconfiguring silently is worse than erroring.
      def slow_effort
        pin('COMRADE_LLM_SLOW_EFFORT') || slow_adaptive
      end

      def slow_adaptive
        words? ? 'high' : 'low'
      end

      # Fast lane effort: the endpoint's own chat template governs
      # (Flash-Next behaves — its defaults are what the bench praised),
      # so unset, empty and 'adaptive' all send no field. 'low'/'high'
      # pin it; unknown fails loudly.
      def fast_effort
        pin('COMRADE_LLM_FAST_EFFORT')
      end

      # The lane pin: 'low'/'high' → the value; unset, empty and
      # 'adaptive' → nil (caller decides); anything unknown raises.
      def pin(env_key)
        value = ENV.fetch(env_key, '').presence
        return value if value.in?(%w[low high])

        unless value.blank? || value == 'adaptive'
          raise UpstreamError, "#{ env_key }: unknown value \"#{ value }\"; use low, high, adaptive, or unset"
        end

        nil
      end

      # The legacy lane's own contract: COMRADE_LLM_REASONING_EFFORT with
      # 'adaptive' treating word and link invocation alike — this is the
      # single-endpoint behavior pre-lanes, kept for unchanged setups.
      def legacy_effort
        value = ENV.fetch('COMRADE_LLM_REASONING_EFFORT', '')
        case value
        when 'adaptive'
          'high' if invoked?
        when 'low', 'high'
          value
        end
      end
    end
  end
end
