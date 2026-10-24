module ConversationsHelper
  # The chat surface: transcript plus query form under one Stimulus root,
  # so the stream-reader controller can reach both. `fresh` marks the
  # index form — its first exchange streams in place, then Turbo visits
  # the conversation's permanent address.
  def chat_surface(endpoint:, fresh:, conversation: nil, messages: [])
    render 'chat', endpoint:, fresh:, conversation:, messages:
  end

  def message_turn(message, tool_notes: [])
    render 'message', message:, tool_notes:
  end

  # One transcript turn: a message plus the tool chips that answer into
  # it. Consecutive tool rows group into the following non-tool message; a
  # tool_calls frame with no spoken content renders nothing and must not
  # flush the chips pending for the answering turn. Tools trailing with no
  # answer become their own bare turns (the partial's stray-row branch
  # renders them).
  # rubocop:disable-next Metrics/MethodLength — one coherent scan; splitting
  # it would hide the grouping shape behind indirection.
  # :reek:TooManyStatements — the grouping walk is one coherent scan.
  def grouped_turns(messages)
    turns = []
    pending = []
    messages.each do |message|
      if message.role == 'tool'
        pending << message
      elsif message.role == 'assistant' && message.tool_payload.present? && message.content.blank?
        # Nothing spoken: render nothing, keep chips pending.
      else
        turns << [message, pending]
        pending = []
      end
    end
    pending.each { |tool| turns << [tool, []] }
    turns
  end

  # The quiet chip text for a tool row: what comrade did, in prose.
  def tool_note(tool)
    if tool.tool_name == 'web_search'
      "searched for #{ tool.tool_payload['arguments']['query'] }"
    else
      "fetched #{ tool.tool_payload['arguments']['url'] }"
    end
  end

  # Answer paragraphs with per-paragraph source chips. Inline [n] markers
  # never render: combined with the model's "Sources:" footer they are the
  # paragraph→source signal, consumed and stripped. A paragraph with no
  # resolvable markers renders bare; the footer itself never renders.
  # Paragraph text is markdown — the model writes markdown — rendered by
  # commonmarker. Raw HTML in the source is escaped by default (no :unsafe),
  # so model output can only produce markdown constructs, never live markup.
  def cited_paragraphs(message)
    citations = message.citations || []
    body, marker_urls = footer_map(message.content)
    paragraphs = body.split(/\n\n+/).map do |paragraph|
      render_answer_paragraph(paragraph, citations, marker_urls)
    end
    safe_join(paragraphs)
  end

  # One answer paragraph: source chips resolved from its [n] markers,
  # text markdown-rendered beneath them.
  def render_answer_paragraph(paragraph, citations, marker_urls)
    plain, urls = paragraph_sources(paragraph, citations, marker_urls)
    block = Commonmarker.to_html(sans_marker_ranges(sans_sup_tags(plain))).strip
    chips = content_tag(:div, source_chips(urls), class: 'mt-1 mb-4 text-xs text-neutral-500') if urls.any?
    # rubocop:disable-next Rails/OutputSafety
    content_tag(:div, block.html_safe, class: 'mb-3 last:mb-0') + chips
  end

  # Strips [n] markers from a paragraph and collects the source hashes
  # they resolve to — canonical citations where the url matches, bare
  # url/title pairs when the model cited something outside the list.
  # :reek:TooManyStatements — the gsub block is one coherent scan.
  def paragraph_sources(paragraph, citations, marker_urls)
    sources = []
    plain = paragraph.gsub(/\[(\d+)\]/) do
      cited = marker_urls[Regexp.last_match(1).to_i]
      sources << source_for(cited, citations) if cited
      ''
    end
    [sans_marker_ranges(sans_sup_tags(plain)), sources.uniq { |source| source['url'] }]
  end

  # jsonb row data — string keys are the storage contract.
  def source_for(cited, citations)
    known = citations.detect { |citation| citation['url'] == cited['url'] }
    return known if known

    # rubocop:disable-next Style/StringHashKeys
    { 'url' => cited['url'],
      'title' => cited['title'] || URI.parse(cited['url']).host, }
  end

  # Inline source chips: title-only links, quiet, one per source.
  def source_chips(sources)
    return ''.html_safe if sources.blank?

    links = sources.map do |source|
      link_to(source['title'] || source['url'],
        source['url'],
        target: '_blank',
        rel: 'noopener',
        class: 'underline hover:text-neutral-300',)
    end
    safe_join(['sources: '.html_safe, safe_join(links, ' · ')])
  end

  # The model sometimes copies the interface's superscript markup into
  # its own text; it renders as escaped noise, so it goes.
  def sans_sup_tags(text)
    text.gsub(%r{</?sup[^>]*>}, '')
  end

  # Range-shaped citation markers ("[1–5]", "[1]–[3]") resolve to no
  # single source, so they'd survive the [n] strip as literal text.
  # Mirrors sansRangeMarkers in stream_reader_controller.js.
  def sans_marker_ranges(text)
    text.gsub(/\[\d+\]\s*[–—-]\s*(?:\[\d+\]|\d+)|\[\d+\s*[–—-]\s*\d+\]/, '')
  end

  # Splits the model's trailing "Sources:" footer off the answer and
  # returns the body plus a { marker number => { url:, title: } } map —
  # the model writes titles into the footer, and they beat bare hosts
  # when the cited url isn't in the canonical citations list.
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
      next unless number && (url = text&.match(%r{https?://\S+})&.to_s)

      # jsonb row data — string keys are the storage contract.
      title = text.sub(url, '').strip.sub(/[—–-]\s*\z/, '').strip
      # rubocop:disable-next Style/StringHashKeys
      map[number.to_i] = { 'url' => url, 'title' => title.presence }
    end
  end

  # :reek:NilCheck — a nil index is the signal: the marker stays as written.
  def marker_index(marker, citations, marker_urls)
    url = marker_urls.dig(marker, 'url')
    return citations.index { |citation| citation['url'] == url }&.next if url

    marker if marker.between?(1, citations.size)
  end
end
