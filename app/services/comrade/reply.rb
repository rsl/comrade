require 'net/http'

module Comrade
  # The reply loop: persists the user message, streams the model's answer
  # from any OpenAI-compatible chat-completions endpoint, and persists the
  # assistant message on clean completion. Yields text deltas as they
  # arrive — the caller owns transport (3a wires them into the response).
  # The system prompt is config, never a row: the shipped voice lives in
  # config/comrade_prompt.md, and a personal comrade_prompt.custom.md
  # (gitignored) overrides it wholesale.
  class Reply
    DEFAULT_PROMPT = Rails.root.join('config/comrade_prompt.md')
    CUSTOM_PROMPT = Rails.root.join('config/comrade_prompt.custom.md')

    # The endpoint is unreachable or misconfigured.
    class UnavailableError < StandardError; end

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

    def append_message(role:, content:)
      @conversation.messages.create!(role: role, content: content)
    end

    private

    def stream_into(yielder)
      answer = +''
      each_delta do |delta|
        answer << delta
        yielder << delta
      end
      append_message(role: 'assistant', content: answer)
    end

    # read_body yields raw TCP chunks whose boundaries ignore SSE event
    # boundaries, so complete lines are buffered out here. The parser keeps
    # only content deltas — role-only frames and (in 2b) tool_call frames
    # arrive without content and are ignored at this layer.
    def each_delta
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

      JSON.parse(payload).dig('choices', 0, 'delta', 'content')
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
