require 'net/http'

module Comrade
  module Tools
    # Web search via SearXNG's JSON API (`?q=&format=json`). Returns the top
    # results as title/url/snippet hashes — the model cites what it used.
    # A missing or unreachable SearXNG is a degraded state, not a crash:
    # the error string flows back to the model, which answers from own
    # knowledge instead.
    class WebSearch
      RESULTS_LIMIT = 5

      def self.call(query:)
        new(query: query).call
      end

      def initialize(query:)
        @query = query
      end

      def call
        return 'Search unavailable: SEARXNG_URL is not set.' if base_url.blank?

        response = fetch_response
        return "Search failed: HTTP #{ response.code }" unless response.is_a?(Net::HTTPSuccess)

        search_results(response)
      rescue JSON::ParserError, Errno::ECONNREFUSED, SocketError, Net::OpenTimeout => error
        "Search failed: #{ error.message }"
      end

      private

      def fetch_response
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
          http.request(Net::HTTP::Get.new(search_uri.request_uri))
        end
      end

      def search_uri
        @search_uri ||= URI.parse("#{ base_url.chomp('/') }/search?#{ query }")
      end

      def search_results(response)
        results = JSON.parse(response.body).fetch('results', []).first(RESULTS_LIMIT)
        return 'No results found.' if results.empty?

        results.map { |result| result.slice('title', 'url', 'content') }
      end

      def query
        # URI.encode_www_form handles escaping; keys are wire params.
        # rubocop:disable Style/StringHashKeys
        URI.encode_www_form('q' => @query, 'format' => 'json')
        # rubocop:enable Style/StringHashKeys
      end

      def uri
        @uri ||= URI.parse(base_url)
      end

      def base_url
        ENV['SEARXNG_URL']
      end
    end
  end
end
