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
end