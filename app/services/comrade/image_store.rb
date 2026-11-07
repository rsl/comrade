module Comrade
  # Reader-attached images: content-hash files on disk, refs on
  # messages.images (jsonb) — the ImageProxy pattern pointed inward.
  # Bytes arrive as data URLs from the staging client, get hashed, and
  # land at storage/uploads/<key>.<ext>: no table, no Active Storage,
  # and the key is the SHA256 of the bytes, so the same image stores
  # once no matter how many turns carry it. A ref describes the wire
  # copy (the downsampled one when the client shrank); when the
  # original differs it rides inside the ref as full: — its own key,
  # type, and dimensions. Full-resolution bytes reach the wire only
  # when the model asks for them (read_image). Serving is same-origin
  # by the unguessable key (/uploads/<key>.<ext>).
  class ImageStore
    MAX_BYTES = 10.megabytes
    # The same render-as-image allowlist the proxy fetches under; SVG
    # stays out for the same reason it stays out there.
    TYPES = ImageProxy::TYPES
    TYPES_BY_MIME = TYPES.invert.freeze
    # The serve grammar: 24-hex key + known extension, nothing else —
    # a user-controlled string never becomes a path.
    SERVE_PATTERN = /\A([0-9a-f]{24})\.(#{ TYPES.keys.join('|') })\z/

    # A staging payload the store won't take: wrong type, empty, or
    # over the cap. Raised before anything streams, so the transport
    # answers 422.
    class Rejected < StandardError; end

    # One attached image as the client stages it: data is the wire
    # copy's data URL, full the original's when staging shrank it,
    # width/height the wire copy's dimensions, source_url a browser
    # drop's provenance. Returns the ref for messages.images —
    # string-keyed, matching how jsonb returns it.
    def self.store(image)
      wire = write_copy(image[:data])
      base_ref(image, wire).merge(full_copy(image, wire)).compact
    end

    private_class_method def self.base_ref(image, wire)
      {
        key: wire[:key],
        ext: wire[:ext].to_s,
        content_type: wire[:content_type],
        width: dimension(image[:width], 'width'),
        height: dimension(image[:height], 'height'),
        source_url: image[:source_url].to_s.presence,
      }.stringify_keys
    end

    # The original rides inside the ref only when it differs from the
    # wire copy — its own key, type, and dimensions.
    private_class_method def self.full_copy(image, wire)
      original = write_copy(image[:full]) if image[:full].present?
      return {} unless original && original[:key] != wire[:key]

      {
        full: {
          key: original[:key],
          ext: original[:ext].to_s,
          content_type: original[:content_type],
          width: dimension(image[:full_width], 'full width'),
          height: dimension(image[:full_height], 'full height'),
        }.stringify_keys,
      }
    end

    # The URL a render fetches one ref's bytes at — same-origin,
    # cacheable forever: a given key's bytes can never change.
    def self.url_for(ref)
      "/uploads/#{ ref['key'] }.#{ ref['ext'] }"
    end

    # The wire shape of one ref: bytes read from disk and base64'd at
    # request time — every turn, every image, so nothing the reader
    # attached ever falls out of the model's sight.
    def self.data_url(ref)
      bytes = path_for(ref).binread
      "data:#{ ref['content_type'] };base64,#{ Base64.strict_encode64(bytes) }"
    end

    # Serve one filename from the uploads directory. The grammar check
    # is the wall send_file's warning is about: only
    # storage/uploads/<24-hex>.<allowlisted ext> can ever come back.
    def self.serve(filename)
      key, ext = filename.to_s.match(SERVE_PATTERN)&.captures
      return unless key

      path = storage_path(key, ext)
      return unless path.exist?

      { path: path, content_type: TYPES.fetch(ext.to_sym) }
    end

    private_class_method def self.write_copy(data_url)
      bytes, ext = decode(data_url)
      key = Digest::SHA256.hexdigest(bytes)[0, 24]
      path = storage_path(key, ext)
      path.dirname.mkpath
      File.binwrite(path, bytes) unless path.exist?
      { key: key, ext: ext, content_type: TYPES.fetch(ext) }
    end

    # The gate: one shape in (a base64 data URL), one of the allowlisted
    # types, empty and over-cap refused. Everything the staging client
    # can send wrong surfaces here as a 422.
    private_class_method def self.decode(data_url)
      mime, payload = data_url.to_s.match(/\Adata:([^;,]+);base64,(.*)\z/m)&.captures
      raise Rejected, 'attachment is not a data URL' unless mime

      bytes = Base64.decode64(payload.to_s)
      ext = TYPES_BY_MIME[mime]
      raise Rejected, "unsupported attachment type: #{ mime }" unless ext
      raise Rejected, 'attachment is empty' if bytes.empty?
      raise Rejected, "attachment is over the #{ MAX_BYTES } byte cap" if bytes.bytesize > MAX_BYTES

      [bytes, ext]
    end

    private_class_method def self.dimension(value, label)
      Integer(value.to_s)
    rescue ArgumentError, TypeError
      raise Rejected, "attachment #{ label } missing"
    end

    private_class_method def self.path_for(ref)
      storage_path(ref.fetch('key'), ref.fetch('ext'))
    end

    private_class_method def self.storage_path(key, ext)
      Rails.root.join('storage', 'uploads', "#{ key }.#{ ext }")
    end
  end
end
