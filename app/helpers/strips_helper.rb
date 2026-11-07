# The transcript's thumbnail strips, both kinds: the image-search rows'
# finds and the user turns' attachments. Extracted from
# ConversationsHelper when the attachment strips pushed it over its
# metric (2026-11-07) — the four builders are one family, and the
# module boundary follows the family.
module StripsHelper
  # The thumbnail strip an image_search row found: proxied thumbs
  # (comrade serves the bytes), tap opens the full image in the
  # lightbox. Sits under the turn's chips, ahead of the answer. The raw
  # source urls live on the row's payload; the proxy derives both
  # addresses.
  def image_strip(tool)
    buttons = tool.tool_payload['images'].to_a.map { |image| strip_button(image) }
    # rubocop:disable-next Rails/OutputSafety — strip_button escapes every
    # interpolated piece; the wrapper literals are static.
    %Q(<div class="image-strip mt-1 mb-3 flex gap-2 overflow-x-auto">#{ buttons.join }</div>).html_safe
  end

  # The attachment strip a user turn carries: the staged copies, served
  # same-origin by content-hash key (ImageStore). Tap opens the
  # lightbox — the full-resolution copy when staging shrank the wire
  # copy. Byte-identical with the stream reader's attachmentStripHtml;
  # the styling is the shared c-attachment-strip class, and image-strip
  # stays the structural hook the lightbox navigates by.
  def attachment_strip(message)
    buttons = message.images.to_a.map { |ref| attachment_button(ref) }
    # rubocop:disable-next Rails/OutputSafety — attachment_button escapes
    # every interpolated piece; the wrapper literals are static.
    %Q(<div class="image-strip c-attachment-strip">#{ buttons.join }</div>).html_safe
  end

  private

  # One thumbnail button, built as raw markup so the render stays
  # byte-identical with the stream reader's imageStripHtml — the
  # post-first-reply Turbo.visit swaps one for the other. Attributes are
  # hand-escaped: titles are model-adjacent text, never trusted.
  # data-thumb-url rides for the lightbox's fallback: when the full-size
  # source can't be served, the known-good thumbnail shows instead.
  def strip_button(image)
    title = html_escape(image['title'].to_s)
    full = html_escape(Comrade::ImageProxy.url_for(image['src']))
    thumb = html_escape(Comrade::ImageProxy.url_for(image['thumbnail']))
    [
      '<button type="button" class="shrink-0 cursor-pointer" data-action="click->lightbox#open" ',
      %Q(data-full-url="#{ full }" data-thumb-url="#{ thumb }" data-caption="#{ title }">),
      %Q(<img src="#{ thumb }" alt="#{ title }" loading="lazy" class="h-24 w-auto rounded">),
      '</button>',
    ].join
  end

  def attachment_button(ref)
    wire = Comrade::ImageStore.url_for(ref)
    full = Comrade::ImageStore.url_for(ref['full'] || ref)
    caption = html_escape(ref['source_url'].presence || 'attached image')
    [
      '<button type="button" class="shrink-0 cursor-pointer" data-action="click->lightbox#open" ',
      %Q(data-full-url="#{ html_escape(full) }" data-thumb-url="#{ html_escape(wire) }" data-caption="#{ caption }">),
      %Q(<img src="#{ html_escape(wire) }" alt="attached image" loading="lazy" class="h-24 w-auto rounded">),
      '</button>',
    ].join
  end
end
