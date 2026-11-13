# The prefs injection is the voice contract's moving part: the base
# prompt is the constitution, prefs are the reader's stated lines on top
# of it, and the commune gets neither beyond the constitution. Mechanics
# specs — what reaches the wire, never what renders.
require 'rails_helper'

RSpec.describe Comrade::Reply do
  before { ENV['COMRADE_LLM_MODEL'] = 'test-model' }

  def system_messages(conversation)
    described_class.new(conversation: conversation, content: 'a question')
      .send(:payload)[:messages].select { |message| message[:role] == 'system' }
  end

  describe 'the prefs injection' do
    it 'layers the comrade\'s prefs as a second system message' do
      rsl = Comrade::Enlistee.create!(name: 'rsl', prefs: { 'jargon' => 'keep it simple — plain words, small pieces' })
      conversation = Conversation.create!(comrade: rsl)

      expect(system_messages(conversation).count).to eq(2)
      expect(system_messages(conversation).last[:content]).to include('keep it simple — plain words, small pieces')
    end

    it 'skips the injection when prefs are empty — factory voice' do
      rsl = Comrade::Enlistee.create!(name: 'rsl')
      conversation = Conversation.create!(comrade: rsl)

      expect(system_messages(conversation).count).to eq(1)
    end

    it 'skips the injection for the commune — no row, no prefs' do
      conversation = Conversation.create!

      expect(system_messages(conversation).count).to eq(1)
    end
  end

  describe 'the citations storage contract' do
    # The [n] markers' ground truth is the wire's own numbering, so the
    # citation list persists in wire order — duplicates included. The
    # render's positional fallback (SourcesHelper.resolution_map) is
    # exact only while this holds; a uniq here silently reintroduces the
    # footerless-answer bug of 2026-11-12 (a repeated url shifted every
    # later marker by one).

    def search_frame(calls)
      tool_calls = calls.each_with_index.to_h do |(name, arguments), index|
        [index, { id: "call_#{ index }", name: name, arguments: JSON.generate(arguments) }]
      end
      { content: nil, tool_calls: tool_calls }
    end

    def drive_reply(conversation, frames, search_results)
      reply = Comrade::Reply.new(conversation: conversation, content: 'a question')
      reply.append_message(role: 'user', content: 'a question')
      allow(Comrade::Reply::TurnLane).to receive(:build).and_return(
        instance_double(Comrade::Reply::TurnLane, kind: 'legacy', model: 'test-model', effort: nil)
      )
      allow(reply).to receive(:stream_pass).and_return(*frames)
      allow(Comrade::Tools::WebSearch).to receive(:call).and_return(*search_results)

      events = []
      reply.enumerator.each { |event| events << event }
      events
    end

    it 'persists citations in wire order, duplicates included' do
      conversation = Conversation.create!
      # Two parallel searches surface the same url once each — the wire
      # numbers it [2] and [3]; both entries must survive to the row.
      frames = [
        search_frame([
          ['web_search', { query: 'lanterns' }],
          ['web_search', { query: 'canceled' }],
        ]),
        { content: 'Answer text', tool_calls: {} },
      ]
      searches = [
        [{ 'title' => 'Forbes', 'url' => 'https://forbes.com/lanterns' },
         { 'title' => 'Complex', 'url' => 'https://complex.com/lanterns' }],
        [{ 'title' => 'Complex again', 'url' => 'https://complex.com/lanterns' },
         { 'title' => 'Polygon', 'url' => 'https://polygon.com/lanterns' }],
      ]

      events = drive_reply(conversation, frames, searches)
      row = conversation.messages.order(:id).last

      expect(row.citations.map { |citation| citation['url'] }).to eq(
        ['https://forbes.com/lanterns', 'https://complex.com/lanterns', 'https://complex.com/lanterns', 'https://polygon.com/lanterns']
      )
      event = events.detect { |e| e[:type] == 'citations' }
      expect(event[:citations].map { |citation| citation[:url] }).to eq(row.citations.map { |citation| citation['url'] })
    end
  end
end