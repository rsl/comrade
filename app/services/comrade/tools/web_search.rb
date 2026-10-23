require 'net/http'

module Comrade
  module Tools
    # Web search via SearXNG's JSON API (`?q=&format=json`). Returns the top
    # results as title/url/snippet hashes — the model cites what it used.
    # A missing or unreachable SearXNG is a degraded state, not a crash:
    # the error string flows back to the model, which answers from own
    # knowledge instead.
    # The upstream engines (brave, duckduckgo, google) throttle bursts hard —
    # a fast model can fire several searches a second and get everything
    # suspended, which reads to it as "no results" and invites more
    # searching. So: a floor between searches, and one patient retry when a
    # query comes back empty.
    class WebSearch
      RESULTS_LIMIT = 5
      # Seconds between upstream queries.
      MIN_SEARCH_INTERVAL = 1.0
      # Seconds before retrying an empty result set.
      THROTTLE_RETRY_DELAY = 4.0

      def self.call(query:)
        return 'Search unavailable: SEARXNG_URL is not set.' if ENV['SEARXNG_URL'].blank?

        new(query: query).call
      end

      # One pace floor for the whole process: parallel tool calls and
      # streamed rounds all queue through it.
      def self.pace
        @lock ||= Mutex.new
        @lock.synchronize do
          @last_search ||= Time.at(0).utc
          gap = Time.now.utc - @last_search
          sleep(MIN_SEARCH_INTERVAL - gap) if gap < MIN_SEARCH_INTERVAL
          @last_search = Time.now.utc
        end
      end

      def initialize(query:)
        @query = query
      end

      # :reek:TooManyStatements — the rescue is one coherent failure path.
      def call
        self.class.pace
        results = fetch_results
        results = retry_after_throttle if results.empty?
        results.empty? ? 'No results found.' : present(results)
      rescue JSON::ParserError, Errno::ECONNREFUSED, SocketError, Net::OpenTimeout => error
        "Search failed: #{ error.message }"
      end

      # Empty usually means upstream engines are suspended, not that nothing
      # exists — one patient retry rides out the throttle window.
      def retry_after_throttle
        sleep(THROTTLE_RETRY_DELAY)
        fetch_results
      end

      private

      def fetch_results
        response = fetch_response
        return [] unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body).fetch('results', [])
      end

      def present(results)
        dedupe(results).first(RESULTS_LIMIT).map { |result| result.slice('title', 'url', 'content') }
      end

      def fetch_response
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
          http.request(Net::HTTP::Get.new(search_uri.request_uri))
        end
      end

      def search_uri
        @search_uri ||= URI.parse("#{ base_url.chomp('/') }/search?#{ query }")
      end

      # Mirrors and syndicated copies repeat snippet text; the repeats read
      # as fresh evidence to the model and feed rabbit holes.
      def dedupe(results)
        seen = Set.new
        results.filter_map do |result|
          key = [result['url'].sub(%r{/+$}, ''), result['content'].to_s[0, 80]]
          next if seen.include?(key)

          seen << key
          result
        end
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
