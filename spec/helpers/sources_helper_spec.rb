# The provenance render contract: how inline [n] markers, the model's
# Sources: footer, and the row's canonical citations combine into the
# turn's margin note card. The paragraphs render bare — markers are
# consumed, sources live in the note (turn_sources/note_card). All
# shapes are hermetic — literal content strings modeled on the
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

      expect(html).to include('The dog comes from a Hunter quest.')
      expect(html).not_to include('[1]')
      expect(html).not_to include('[2]')
      expect(html).not_to include('href=')

      expect(helper.turn_sources(answer)).to eq(
        [
          { 'n' => 1, 'url' => 'https://ign.com/wikis/enshrouded/Dog_Search', 'title' => 'IGN Dog Search' },
          { 'n' => 2, 'url' => 'https://dotesports.com/enshrouded/taming', 'title' => 'Taming Guide' },
        ],
      )
    end

    it 'resolves through a declared footer even when it disagrees with the wire numbering' do
      answer = Answer.new(
        "Rumors spread [1].\n\nSources:\n[1] Polygon — https://polygon.com/lanterns",
        [{ 'url' => 'https://forbes.com/lanterns', 'title' => 'Forbes' }],
      )

      html = helper.cited_paragraphs(answer)

      expect(html).to include('Rumors spread.')

      expect(helper.turn_sources(answer)).to eq(
        [{ 'n' => 1, 'url' => 'https://polygon.com/lanterns', 'title' => 'Polygon' }],
      )
    end

    it 'leaves a marker past the list literal — no invented source' do
      answer = Answer.new(
        'Season 2 is undecided [7].',
        [{ 'url' => 'https://forbes.com/lanterns', 'title' => 'Forbes' }],
      )

      html = helper.cited_paragraphs(answer)

      expect(html).to include('Season 2 is undecided [7].')
      expect(helper.turn_sources(answer)).to be_empty
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

    it 'falls back to the declared footer list when no marker resolved' do
      answer = Answer.new(
        "The fix isn't a different farm spot.\n\nSources:\n[1] Wiki — https://enshrouded.wiki.gg/gems",
        [{ 'url' => 'https://enshrouded.wiki.gg/gems', 'title' => 'Gem Wiki' }],
      )

      html = helper.cited_paragraphs(answer)

      expect(html).to include("The fix isn't a different farm spot.")
      expect(html).not_to include('href=')

      expect(helper.turn_sources(answer)).to eq(
        [{ 'n' => 1, 'url' => 'https://enshrouded.wiki.gg/gems', 'title' => 'Gem Wiki' }],
      )
    end

    it 'collapses two markers that resolve to one url into one source' do
      answer = Answer.new(
        'The map is an estimate [1], and it spread through reposts [3].',
        [
          { 'url' => 'https://tiktok.com/map', 'title' => 'The Map' },
          { 'url' => 'https://instagram.com/repost', 'title' => 'Repost' },
          { 'url' => 'https://tiktok.com/map', 'title' => 'The Map Again' },
        ],
      )

      html = helper.cited_paragraphs(answer)

      expect(html).to include('The map is an estimate, and it spread through reposts.')

      expect(helper.turn_sources(answer)).to eq(
        [{ 'n' => 1, 'url' => 'https://tiktok.com/map', 'title' => 'The Map' }],
      )
    end

    it 'renders the none line on a knowledge-only answer' do
      answer = Answer.new(
        'Season 1 is done; season 2 is undecided.',
        [{ 'url' => 'https://forbes.com/lanterns', 'title' => 'Forbes' }],
      )

      html = helper.note_card({ answer: answer, note: 3 })

      expect(html).to include('none — from model knowledge')
      expect(html).not_to include('href=')
    end
  end
end