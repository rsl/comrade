module MessagesHelper
  # The inspector's JSON, with long strings elided — attached images
  # ride the real request as base64 data URLs, and the reconstruction
  # is exact, but the page has no business printing megabytes of
  # base64. Everything under the cap renders whole.
  def wire_request_json(request)
    JSON.pretty_generate(elide_long_strings(request))
  end

  private

  def elide_long_strings(value)
    case value
    when String
      value.length > 200 ? "#{ value.first(96) }…(#{ value.length } chars)" : value
    when Array
      value.map { |item| elide_long_strings(item) }
    when Hash
      value.transform_values { |item| elide_long_strings(item) }
    else
      value
    end
  end
end
