module Comrade
  module Tools
    # Full-page extraction via Tavily's extract API. Returns the page's raw
    # content (truncated — a tool result is prompt material, not storage)
    # so the model can read past the snippet.
    class FetchPage
      CONTENT_LIMIT = 8_000

      def self.call(url:)
        new(url: url).call
      end

      def initialize(url:)
        @url = url
      end

      def call
        return 'Fetch unavailable: TAVILY_API_KEY is not set.' if api_key.blank?

        response = fetch_response
        return "Fetch failed: HTTP #{ response.code }" unless response.is_a?(Net::HTTPSuccess)

        extracted_content(response)
      rescue JSON::ParserError, Errno::ECONNREFUSED, SocketError, Net::OpenTimeout, URI::InvalidURIError => error
        "Fetch failed: #{ error.message }"
      end

      private

      def fetch_response
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
          http.request(post_request)
        end
      end

      def extracted_content(response)
        content = JSON.parse(response.body).dig('results', 0, 'raw_content')
        return 'No content extracted.' if content.blank?

        content.first(CONTENT_LIMIT)
      end

      def post_request
        request = Net::HTTP::Post.new(uri.request_uri, headers)
        # Keys are wire params.
        request.body = { urls: [@url] }.to_json
        request
      end

      def headers
        # Header names are strings on the wire.
        # rubocop:disable Style/StringHashKeys
        {
          'Content-Type' => 'application/json',
          'Authorization' => "Bearer #{ api_key }",
        }
        # rubocop:enable Style/StringHashKeys
      end

      def uri
        @uri ||= URI.parse('https://api.tavily.com/extract')
      end

      def api_key
        ENV['TAVILY_API_KEY']
      end
    end
  end
end
