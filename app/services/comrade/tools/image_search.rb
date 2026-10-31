require 'net/http'

module Comrade
  module Tools
    # Image search via SearXNG's JSON API (`?q=&format=json&categories=images`).
    # Returns the top results as title/page/src/thumbnail hashes — src and
    # thumbnail are the picture's own addresses (full-size and preview);
    # the model gets titles and page urls only, and the reader gets the
    # pictures as thumbnails through the proxy. Same degraded state as
    # WebSearch: a missing or unreachable SearXNG is an error string, not
    # a crash — the error flows back to the model, which answers without
    # pictures. Shares the Pacing floor (same SearXNG, same throttles).
    class ImageSearch
      RESULTS_LIMIT = 6
      # Seconds before retrying an empty result set.
      THROTTLE_RETRY_DELAY = 4.0
      # Smallest reported dimension a result may have — below this,
      # thumbnails and lightbox fallbacks turn to mush. Tunable (rsl).
      MIN_DIMENSION = 200

      def self.call(query:)
        return 'Image search unavailable: COMRADE_SEARCH_URL is not set.' if ENV['COMRADE_SEARCH_URL'].blank?

        new(query: query).call
      end

      def initialize(query:)
        @query = query
      end

      # :reek:TooManyStatements — the rescue is one coherent failure path.
      def call
        Pacing.pace
        results = fetch_results
        results = retry_after_throttle if results.empty?
        results.empty? ? 'No images found.' : present(results)
      rescue JSON::ParserError, Errno::ECONNREFUSED, SocketError, Net::OpenTimeout => error
        "Image search failed: #{ error.message }"
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
        pictures = results.filter_map { |result| picture_in(result) }
        pictures.first(RESULTS_LIMIT)
      end

      # Image rows carry the picture twice: a full-size src and (usually)
      # a smaller thumbnail; thumbnail falls back to src. Rows with no
      # picture at all are dead weight — dropped.
      def picture_in(result)
        src = absolute(result['img_src'])
        return unless src
        return unless big_enough?(result)

        { title: result['title'].to_s,
          page: result['url'].to_s,
          src: src,
          thumbnail: absolute(result['thumbnail_src']) || src, }
      end

      # SearXNG's image engines report each picture's resolution
      # ("2000×1335"); below the floor, tiny icons and spacer gifs never
      # reach the reader. Results reporting no resolution stay in — the
      # engines that don't measure tend to return real pictures.
      def big_enough?(result)
        return true if result['resolution'].blank?

        width, height = result['resolution'].to_s.split(/[x×]/i).map(&:to_i)
        return false if width.zero? || height.zero?

        [width, height].min >= MIN_DIMENSION
      end

      # Some engines return protocol-relative or root-relative picture
      # paths — resolve both against the SearXNG host's scheme/origin.
      def absolute(url)
        return if url.blank?
        return "https:#{ url }" if url.start_with?('//')
        return "#{ base_url.chomp('/') }#{ url }" if url.start_with?('/')

        url
      end

      def fetch_response
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
          http.request(Net::HTTP::Get.new(search_uri.request_uri))
        end
      end

      def search_uri
        @search_uri ||= URI.parse("#{ base_url.chomp('/') }/search?#{ query }")
      end

      def query
        # URI.encode_www_form handles escaping; keys are wire params.
        # rubocop:disable-next Style/StringHashKeys
        URI.encode_www_form('q' => @query, 'format' => 'json', 'categories' => 'images')
      end

      def uri
        @uri ||= URI.parse(base_url)
      end

      def base_url
        ENV['COMRADE_SEARCH_URL']
      end
    end
  end
end
