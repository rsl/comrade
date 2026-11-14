# The provenance half of the transcript render: the model's "Sources:"
# footer, the inline [n] markers it keys, the margin-note card they fill,
# and the tool chips that record what comrade did to earn the answer.
# Split from ConversationsHelper on the module-length gate —
# the twins in stream_reader_controller.js mirror these methods.
module SourcesHelper
  # The quiet chip text for a tool row: what comrade did, in prose, with
  # the variable part emphasized. Byte-shape twin of the stream reader's
  # toolChip.
  def tool_note(tool)
    label, value = tool_note_parts(tool)
    safe_join([label, ' ', tag.em(value)])
  end

  def tool_note_parts(tool)
    args = tool.tool_payload['arguments']
    case tool.tool_name
    when 'web_search' then ['searched for:', args['query']]
    when 'image_search' then ['searched images for:', args['query']]
    when 'read_image' then ['read image:', args['key']]
    else ['fetched:', args['url']]
    end
  end

  # Answer paragraphs, markdown-rendered. Inline [n] markers never render
  # in the text: combined with the model's "Sources:" footer they are the
  # paragraph→source signal, consumed and stripped — the sources they
  # signal live in the turn's margin note card (note_card), not under the
  # paragraphs. A marker that resolves to nothing stays literal, as
  # before. Paragraph text is markdown — the model writes markdown —
  # rendered by commonmarker. Raw HTML in the source is escaped by
  # default (no :unsafe), so model output can only produce markdown
  # constructs, never live markup.
  def cited_paragraphs(message)
    citations = message.citations || []
    body, footer_urls = footer_map(message.content)
    marker_urls, = resolution_map(footer_urls, citations)
    safe_join(
      body.split(/\n\n+/).reject(&:blank?).map do |paragraph|
        plain = strip_resolved_markers(paragraph, marker_urls)
        block = Commonmarker.to_html(sans_marker_ranges(sans_sup_tags(plain))).strip
        # rubocop:disable-next Rails/OutputSafety
        block.html_safe
      end,
    )
  end

  # The map paragraphs resolve [n] against, plus whether a declared
  # footer produced it. The model's footer wins when it exists: its
  # numbering is the model's own declaration, even a partial one. When
  # the footer was skipped — the fast lane's habit on ~1 answer in 4 —
  # the wire numbering is the ground truth: citations persist in wire
  # order (reply.rb), so [n] is citations[n-1].
  def resolution_map(footer_urls, citations)
    return [footer_urls, true] if footer_urls.present?

    [positional_map(citations), false]
  end

  # The wire's [n]→source map, from citations stored in wire order: [n]
  # numbered the tool results this turn streamed, and the citation list
  # records them one for one. A marker past the list (the model invented
  # a number, or an old row's pre-dedupe numbering) resolves to nothing
  # and strips bare, as before.
  def positional_map(citations)
    citations.each_with_index.to_h { |citation, index| [index + 1, citation] }
  end

  # Strips the [n] markers that resolve through the map — the whitespace
  # before a marker goes with it, so "word [3]." renders "word.", never
  # "word .". Unresolvable markers stay literal. Byte-shape twin of the
  # marker pass in the stream reader's renderCitations.
  def strip_resolved_markers(paragraph, marker_urls)
    paragraph.gsub(/\s*\[(\d+)\]/) do
      marker_urls.key?(Regexp.last_match(1).to_i) ? '' : Regexp.last_match(0)
    end
  end

  # The turn's sources for its margin note card: the union of the
  # paragraphs' marker resolutions in first-appearance order, deduped by
  # url, each carrying the marker number that first cited it. Deep-lane
  # drift (a declared footer with no inline markers) falls back to the
  # footer's own declared list, resolved and deduped exactly like the
  # inline markers — the trailing-chip fallback's heir. Byte-shape twin
  # of the noteSources walk in the stream reader's renderCitations.
  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity — one coherent scan over the paragraphs' markers; the forks are the footer/positional map and the drift fallback.
  # :reek:TooManyStatements — the source walk is one coherent scan.
  def turn_sources(message)
    citations = message.citations || []
    body, footer_urls = footer_map(message.content)
    marker_urls, = resolution_map(footer_urls, citations)
    sources = []
    remember = ->(number, cited) {
      source = source_for(cited, citations)
      next if sources.any? { |known| known['url'] == source['url'] }

      # rubocop:disable-next Style/StringHashKeys
      sources << { 'n' => number, 'url' => source['url'], 'title' => source['title'] }
    }
    body.split(/\n\n+/).each do |paragraph|
      paragraph.scan(/\[(\d+)\]/).map(&:first).map(&:to_i).each do |number|
        cited = marker_urls[number]
        remember.call(number, cited) if cited
      end
    end
    if sources.empty? && footer_urls.present?
      footer_urls.sort.each { |number, cited| remember.call(number, cited) }
    end
    sources
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

  # The margin-note card itself: the note number, then one line per
  # source — marker, title link, go-deeper — or the "none" line when the
  # answer drew on model knowledge alone. Byte-shape twin of the stream
  # reader's fillNote.
  def note_card(exchange)
    answer = exchange[:answer]
    return '' unless answer

    sources = turn_sources(answer)
    lines = sources.map { |source| note_line(source) }
    lines << tag.span('none — from model knowledge', class: 'c-note-line') if sources.empty?
    tag.div class: 'c-note' do
      safe_join([tag.b(format('%02d', exchange[:note]), class: 'c-note-num'), safe_join(lines)])
    end
  end

  def note_line(source)
    title = link_to(source['title'] || source['url'], source['url'], target: '_blank', rel: 'noopener')
    deeper = link_to(
      'go deeper',
      '#',
      data: { title: source['title'], url: source['url'] },
      data_action: 'stream-reader#goDeeper',
      class: 'go-deeper',
    )
    tag.span(safe_join([tag.em(source['n']), ' · ', title, ' ', deeper]), class: 'c-note-line')
  end

  # jsonb row data — string keys are the storage contract.
  def source_for(cited, citations)
    known = citations.detect { |citation| citation['url'] == cited['url'] }
    return known if known

    # rubocop:disable-next Style/StringHashKeys
    {
      'url' => cited['url'],
      'title' => cited['title'] || URI.parse(cited['url']).host,
    }
  end

  # The model sometimes copies the interface's superscript markup into
  # its own text; it renders as escaped noise, so it goes.
  def sans_sup_tags(text)
    text.gsub(%r{</?sup[^>]*>}, '')
  end

  # Range-shaped citation markers ("[1–5]", "[1]–[3]") resolve to no
  # single source, so they'd survive the [n] strip as literal text.
  # The whitespace before the range goes with it — same rule as the
  # [n] strip in strip_resolved_markers ("word [1–5]." renders "word.").
  # Mirrors sansRangeMarkers in stream_reader_controller.js.
  def sans_marker_ranges(text)
    text.gsub(/\s*\[\d+\]\s*[–—-]\s*(?:\[\d+\]|\d+)|\s*\[\d+\s*[–—-]\s*\d+\]/, '')
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
end
