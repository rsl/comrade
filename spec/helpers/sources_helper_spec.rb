# The provenance render contract: how inline [n] markers, the model's
# Sources: footer, and the row's canonical citations combine into source
# chips. All shapes are hermetic — literal content strings modeled on the
# real failing rows (fast-lane footerless answers, 2026-11-12). The JS
# twin (renderCitations) is review-locked, not spec-locked.
require 'rails_helper'

RSpec.describe SourcesHelper, type: :helper do
  Answer = Struct.new(:content, :citations)

  describe '#cited_paragraphs' do
    it 'resolves markers positionally when the model skipped its footer' do
      answer = Answer.new(
        "The dog comes from a Hunter quest [1].\n\nThe bait is made by Emily Fray [2].",
        [
          { 'url' => 'https://ign.com/wikis/enshrouded/Dog_Search', 'title' => 'IGN Dog Search' },
          { 'url' => 'https://dotesports.com/enshrouded/taming', 'title' => 'Taming Guide' },
        ],
      )

      html = helper.cited_paragraphs(answer)

      expect(html).to include('href="https://ign.com/wikis/enshrouded/Dog_Search"')
      expect(html).to include('href="https://dotesports.com/enshrouded/taming"')
      expect(html).to include('IGN Dog Search')
      expect(html).not_to include('[1]')
      expect(html).not_to include('[2]')
    end

    it 'resolves through a declared footer even when it disagrees with the wire numbering' do
      answer = Answer.new(
        "Rumors spread [1].\n\nSources:\n[1] Polygon — https://polygon.com/lanterns",
        [{ 'url' => 'https://forbes.com/lanterns', 'title' => 'Forbes' }],
      )

      html = helper.cited_paragraphs(answer)

      expect(html).to include('href="https://polygon.com/lanterns"')
      expect(html).not_to include('href="https://forbes.com/lanterns"')
    end

    it 'strips a marker past the list bare — no invented chip' do
      answer = Answer.new(
        'Season 2 is undecided [7].',
        [{ 'url' => 'https://forbes.com/lanterns', 'title' => 'Forbes' }],
      )

      html = helper.cited_paragraphs(answer)

      expect(html).not_to include('[7]')
      expect(html).not_to include('sources: ')
    end

    it 'never auto-renders the canonical citations when the model wrote no markers' do
      answer = Answer.new(
        'Season 1 is done; season 2 is undecided.',
        [
          { 'url' => 'https://forbes.com/lanterns', 'title' => 'Forbes' },
          { 'url' => 'https://polygon.com/lanterns', 'title' => 'Polygon' },
        ],
      )

      html = helper.cited_paragraphs(answer)

      expect(html).to include('Season 1 is done')
      expect(html).not_to include('sources: ')
    end

    it 'renders the declared footer as a trailing line when no marker resolved' do
      answer = Answer.new(
        "The fix isn't a different farm spot.\n\nSources:\n[1] Wiki — https://enshrouded.wiki.gg/gems",
        [{ 'url' => 'https://enshrouded.wiki.gg/gems', 'title' => 'Gem Wiki' }],
      )

      html = helper.cited_paragraphs(answer)

      expect(html).not_to include('Sources:')
      expect(html).to include('sources: ')
      expect(html).to include('href="https://enshrouded.wiki.gg/gems"')
    end

    it 'collapses two markers that resolve to one url into one chip' do
      answer = Answer.new(
        'The map is an estimate [1], and it spread through reposts [3].',
        [
          { 'url' => 'https://tiktok.com/map', 'title' => 'The Map' },
          { 'url' => 'https://instagram.com/repost', 'title' => 'Repost' },
          { 'url' => 'https://tiktok.com/map', 'title' => 'The Map Again' },
        ],
      )

      html = helper.cited_paragraphs(answer)

      expect(html.scan('href="https://tiktok.com/map"').count).to eq(1)
      expect(html).to include('The Map')
      expect(html).not_to include('The Map Again')
    end
  end
end