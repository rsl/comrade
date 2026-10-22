module ConversationsHelper
  # The chat surface: transcript plus query form under one Stimulus root,
  # so the stream-reader controller can reach both. `fresh` marks the
  # index form — its first exchange streams in place, then Turbo visits
  # the conversation's permanent address.
  def chat_surface(endpoint:, fresh:, conversation: nil, messages: [])
    render 'chat', endpoint:, fresh:, conversation:, messages:
  end

  def message_turn(message)
    render 'message', message:
  end

  def recent_conversations(conversations)
    render 'recent', conversations:
  end

  # Answer text with [n] markers rendered as superscript links into the
  # message's numbered source list. Paragraphs split on blank lines.
  # The model tends to append its own "Sources:" footer and number
  # markers against it, regardless of the tool-layer numbering. The
  # footer is parsed into a marker→url map and stripped; each marker is
  # then rewritten to point at the matching entry in the canonical
  # citation list. Without a footer, a marker is read as a direct index.
  def cited_paragraphs(message)
    citations = message.citations || []
    body, marker_urls = footer_map(message.content)
    # html_safe is sound: the paragraph ran through h() and the only
    # interpolation added is link_markers' own anchor markup.
    paragraphs = body.split(/\n\n+/).map do |paragraph|
      marked = link_markers(h(sans_sup_tags(paragraph)), citations, marker_urls)
      # The only html_safe content is h()'d text plus link_markers' own
      # anchor markup — no model-controlled raw HTML survives escaping.
      # rubocop:disable Rails/OutputSafety
      content_tag(:p, marked.html_safe, class: 'mb-3 last:mb-0')
      # rubocop:enable Rails/OutputSafety
    end
    safe_join(paragraphs)
  end

  # The model sometimes copies the interface's superscript markup into
  # its own text; it renders as escaped noise, so it goes.
  def sans_sup_tags(text)
    text.gsub(%r{</?sup[^>]*>}, '')
  end

  # Splits the model's trailing "Sources:" footer off the answer and
  # returns the body plus a { marker number => url } map.
  def footer_map(content)
    map = {}
    body = content.to_s.sub(/\n?Sources?:\n((?:\s*\[\d+\][^\n]*\n?)+)\s*\z/) do
      parse_footer_lines(Regexp.last_match(1), map)
      "\n"
    end
    [body, map]
  end

  def parse_footer_lines(footer_block, map)
    footer_block.each_line do |line|
      number, text = line.match(/^\s*\[(\d+)\]\s*(.+)$/)&.captures
      url = text&.match(%r{https?://\S+})&.to_s
      map[number.to_i] = url if number && url
    end
  end

  # :reek:NilCheck — a nil index is the signal: the marker stays as written.
  def link_markers(escaped_paragraph, citations, marker_urls)
    escaped_paragraph.gsub(/\[(\d+)\]/) do
      marker = Regexp.last_match(1).to_i
      index = marker_index(marker, citations, marker_urls)
      # A nil index — no footer entry, out of range — leaves the marker
      # as the model wrote it.
      next Regexp.last_match(0) if index.nil?

      %Q(<sup><a href="#src-#{ index }" class="hover:text-neutral-300">#{ index }</a></sup>)
    end
  end

  # :reek:NilCheck — a nil index means the marker stays as written.
  def marker_index(marker, citations, marker_urls)
    url = marker_urls[marker]
    return citations.index { |citation| citation['url'] == url }&.next if url

    marker if marker.between?(1, citations.size)
  end

  # The numbered source list that [n] anchors point into.
  def cited_sources(message)
    citations = message.citations || []
    return if citations.blank?

    items = citations.each_with_index.map do |citation, index|
      link = link_to(citation['title'] || citation['url'],
        citation['url'],
        target: '_blank',
        rel: 'noopener',
        class: 'underline hover:text-neutral-300',)
      content_tag(:li, link, id: "src-#{ index + 1 }")
    end
    tag.ol(safe_join(items), class: 'list-decimal ml-4 space-y-0.5')
  end
end
