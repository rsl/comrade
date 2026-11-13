# The provenance half of the transcript render: the model's "Sources:"
# footer, the inline [n] markers it keys, and the quiet chip lines they
# become. Split from ConversationsHelper on the module-length gate —
# the twins in stream_reader_controller.js mirror these methods.
module SourcesHelper
  # Answer paragraphs with per-paragraph source chips. Inline [n] markers
  # never render: combined with the model's "Sources:" footer they are the
  # paragraph→source signal, consumed and stripped. A paragraph with no
  # resolvable markers renders bare; the footer itself never renders.
  # Paragraph text is markdown — the model writes markdown — rendered by
  # commonmarker. Raw HTML in the source is escaped by default (no :unsafe),
  # so model output can only produce markdown constructs, never live markup.
  def cited_paragraphs(message)
    citations = message.citations || []
    body, footer_urls = footer_map(message.content)
    marker_urls, footer_declared = resolution_map(footer_urls, citations)

    # A leading blank run in the persisted content (older answers carry
    # "\n\n" from the endpoint's chat template) splits into an empty first
    # paragraph — a phantom mb-3 div. Blank segments never render.
    paragraphs = body.split(/\n\n+/).reject(&:blank?).map do |paragraph|
      render_answer_paragraph(paragraph, citations, marker_urls)
    end
    # The trailing-list fallback stays tied to a declared footer: without
    # one, the canonical citations include tool-gathered sources the
    # answer may never have used, and auto-rendering them would claim
    # provenance the model never declared.
    paragraphs << footer_fallback(marker_urls, citations) if footer_declared && fallback_due?(body, marker_urls)
    safe_join(paragraphs)
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

  # Deep-lane drift: the model declares a "Sources:" footer but never
  # marks the paragraphs inline, so the render contract strips the footer
  # and provenance vanishes (conv 59). Conservative fallback — the
  # footer's own declared list becomes a trailing chip line. Called only
  # for a declared footer (the caller guards with footer_declared) — a
  # footerless answer never auto-renders its canonical citations.
  def fallback_due?(body, marker_urls)
    marker_urls.present? && !markers_resolve?(body, marker_urls)
  end

  # Exactly the condition that renders paragraph chips: at least one
  # inline [n] marker resolving through the footer map.
  def markers_resolve?(body, marker_urls)
    body.scan(/\[(\d+)\]/).any? { |(number)| marker_urls.key?(number.to_i) }
  end

  # The trailing chip line itself: the footer's entries in marker order,
  # resolved the way markers are (canonical citations win on url match,
  # titles beat bare hosts), deduped by url. Same wrapper classes as the
  # per-paragraph chip lines — byte-identical with the stream reader's
  # footerSources append in renderCitations.
  def footer_fallback(marker_urls, citations)
    sources = marker_urls.sort.map { |_, cited| source_for(cited, citations) }.uniq { |source| source['url'] }
    content_tag(:div, source_chips(sources), class: 'mt-1 mb-4 text-xs text-neutral-500')
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
  # The whitespace before a marker goes with it, so "word [3]." renders
  # "word.", never "word ." — the marker sat between the space and the
  # punctuation, and the space belongs to the marker, not the word.
  # :reek:TooManyStatements — the gsub block is one coherent scan.
  def paragraph_sources(paragraph, citations, marker_urls)
    sources = []
    plain = paragraph.gsub(/\s*\[(\d+)\]/) do
      # The block's return value is the replacement text: each marker
      # vanishes from the rendered paragraph, and only its source hash
      # (collected above, when it resolves) survives into the chips.
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
    {
      'url' => cited['url'],
      'title' => cited['title'] || URI.parse(cited['url']).host,
    }
  end

  # Inline source chips: title-only links, quiet, one per source. Each
  # carries a go-deeper affordance — the twins in stream_reader_controller.js
  # (sourceChips) must stay byte-shape-identical with this markup; the post-
  # first-reply Turbo.visit and the streaming path swap them freely.
  def source_chips(sources)
    return ''.html_safe if sources.blank?

    links = sources.map do |source|
      title = link_to(
        source['title'] || source['url'],
        source['url'],
        target: '_blank',
        rel: 'noopener',
        class: 'underline hover:text-neutral-300',
      )
      deeper = link_to(
        'go deeper',
        '#',
        data: { title: source['title'], url: source['url'] },
        data_action: 'stream-reader#goDeeper',
        class: 'go-deeper cursor-pointer underline hover:text-neutral-300',
      )
      safe_join([title, deeper], ' · ')
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
  # The whitespace before the range goes with it — same rule as the
  # [n] strip in paragraph_sources ("word [1–5]." renders "word.").
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
