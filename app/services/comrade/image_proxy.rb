require 'net/http'

module Comrade
  # The image proxy: comrade fetches and serves images itself — devices
  # never talk to image hosts directly (no viewer IP leaks, no hotlink
  # blocks, same-origin bytes for every fleet device). A proxied URL is
  # the source URL plus a truncated HMAC signature — /img/<key>?p=<url> —
  # so the proxy serves only the URLs comrade itself surfaced: no table,
  # no Active Storage, and nothing forgeable. Fetched copies cache under
  # storage/images/<key>.<ext>; no cleanup rule yet (parked rider — disk
  # is cheap here, revisit when it isn't).
  class ImageProxy
    MAX_BYTES = 10.megabytes
    # Extension → content type: the fetch allowlists by type, the serve
    # maps the cached extension back. AVIF is admitted — 2026 CDNs serve
    # full images as avif by default while their thumbnails ride a
    # re-encoding CDN, so rejecting it broke exactly the lightbox images
    # whose thumbnails worked. SVG is deliberately excluded: an inline
    # SVG from a foreign origin is a script-execution vector.
    TYPES = { jpg: 'image/jpeg', png: 'image/png', gif: 'image/gif', webp: 'image/webp', avif: 'image/avif' }.freeze
    FETCH_TIMEOUTS = { open_timeout: 10, read_timeout: 20 }.freeze
    MAX_REDIRECTS = 3
    # Everything an unreachable or broken source can raise — the fetch
    # treats all of it the same: no bytes, no picture.
    SOURCE_ERRORS = [
      URI::InvalidURIError,
      SocketError,
      Net::OpenTimeout,
      Net::ReadTimeout,
      Errno::ECONNREFUSED,
      EOFError,
    ].freeze

    def self.authorized?(url, key)
      ActiveSupport::SecurityUtils.secure_compare(key_for(url), key.to_s)
    end

    def self.url_for(url)
      "/img/#{ key_for(url) }?p=#{ URI.encode_www_form_component(url) }"
    end

    # The wire shape of one image result: raw source urls stay in the
    # row's jsonb (data), proxied urls ride the event and the strip
    # (presentation).
    def self.view(image)
      {
        title: image[:title].to_s,
        page: image[:page].to_s,
        full: url_for(image[:src]),
        thumb: url_for(image[:thumbnail]),
      }
    end

    # The bytes for a signed source: the cached copy when one exists,
    # a fresh fetch-and-cache when not. Nil when the source can't be
    # served (bad scheme, wrong type, unreachable, oversized) — the
    # controller answers bad_gateway and the img just shows broken.
    def self.retrieve(url)
      uri = servable_uri(url)
      return unless uri

      key = key_for(url)
      cached_copy(key) || fetch_and_cache(uri, key)
    rescue *SOURCE_ERRORS
      nil
    end

    private_class_method def self.servable_uri(url)
      uri = URI.parse(url)
      uri if uri.scheme.in?(%w[http https])
    rescue URI::InvalidURIError
      nil
    end

    private_class_method def self.serve_cached(key, ext)
      { path: cache_path(key, ext), content_type: TYPES.fetch(ext) }
    end

    private_class_method def self.cached_copy(key)
      ext = cached_extension(key)
      serve_cached(key, ext) if ext
    end

    private_class_method def self.key_for(url)
      OpenSSL::HMAC.hexdigest('SHA256', Rails.application.secret_key_base, url.to_s)[0, 24]
    end

    private_class_method def self.cached_extension(key)
      TYPES.keys.detect { |ext| File.exist?(cache_path(key, ext)) }
    end

    private_class_method def self.fetch_and_cache(uri, key, redirects=MAX_REDIRECTS)
      response = fetch(uri)
      return follow_redirect(response, key, redirects) if response.is_a?(Net::HTTPRedirection)
      return unless response.is_a?(Net::HTTPSuccess)

      cache(response, key)
    rescue *SOURCE_ERRORS
      nil
    end

    private_class_method def self.follow_redirect(response, key, redirects)
      return if redirects.zero?

      fetch_and_cache(URI.parse(response['Location']), key, redirects - 1)
    end

    # The type must be one the browser renders as an image and the body
    # within the cap — then the copy is cached and served from disk.
    # Rejections log: the silent-swallow version turned "why is this
    # image broken?" into archaeology (2026-10-31).
    private_class_method def self.cache(response, key)
      ext = TYPES.key(normalized_type(response))
      return reject(key, "content-type #{ normalized_type(response) }") unless ext

      body = response.body
      return reject(key, "#{ body.bytesize } bytes over cap") if body.bytesize > MAX_BYTES

      write_cache(key, ext, body)
    end

    private_class_method def self.normalized_type(response)
      type = response['Content-Type'].to_s.split(';').first
      # Some servers send the nonstandard "image/jpg"; same format.
      type == 'image/jpg' ? 'image/jpeg' : type
    end

    private_class_method def self.reject(key, reason)
      Rails.logger.info("[image_proxy] rejected #{ key }: #{ reason }")
      nil
    end

    private_class_method def self.write_cache(key, ext, body)
      path = cache_path(key, ext)
      path.dirname.mkpath
      File.write(path, body, mode: 'wb')
      { path: path, content_type: TYPES.fetch(ext) }
    end

    private_class_method def self.fetch(uri)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', **FETCH_TIMEOUTS) do |http|
        http.request(Net::HTTP::Get.new(uri.request_uri))
      end
    end

    private_class_method def self.cache_path(key, ext)
      Rails.root.join('storage', 'images', "#{ key }.#{ ext }")
    end
  end
end
