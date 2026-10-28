# The calibration loop: the canned simplification turn counts, the count
# proposes, one quiet offer, and the party line is the reader's own
# directive. Mechanics — records and gates, never page content.
require 'rails_helper'

RSpec.describe 'Calibration and party line', type: :request do
  let(:canned) { Comrade::Enlistee::BREAK_DOWN_TURN }

  def enlist(name = 'rsl')
    post '/enlistment', params: { name: name }
  end

  describe 'the break-it-down count' do
    it 'counts the canned turn, not other messages' do
      enlist
      rsl = Comrade::Enlistee.find_by(name: 'rsl')
      conversation = Conversation.create!(comrade: rsl)

      post "/conversations/#{conversation.id}/messages", params: { content: 'something else entirely' }
      post "/conversations/#{conversation.id}/messages", params: { content: canned }
      post "/conversations/#{conversation.id}/messages", params: { content: "  #{canned}  " }

      expect(rsl.reload.calibration['break_down']).to eq(2)
    end

    it 'does not count for the commune — no row to hang it on' do
      conversation = Conversation.create!

      post "/conversations/#{conversation.id}/messages", params: { content: canned }

      expect(Comrade::Enlistee.count).to eq(0)
    end
  end

  describe 'the one quiet offer' do
    # The offer lives under the latest answer, so every assertion needs a
    # conversation page carrying one.
    def conversation_with_answer
      enlist
      conversation = Conversation.create!(comrade: Comrade::Enlistee.find_by(name: 'rsl'))
      conversation.messages.create!(role: 'assistant', content: 'an answer worth simplifying')
      conversation
    end

    it 'stays quiet below the threshold' do
      conversation = conversation_with_answer
      Comrade::Enlistee.find_by(name: 'rsl')
        .update!(calibration: { 'break_down' => Comrade::Enlistee::NUDGE_THRESHOLD - 1 })

      get "/conversations/#{conversation.id}"
      expect(response.body).not_to include('Simpler by default?')
    end

    it 'offers once at the threshold, then never again when ignored' do
      conversation = conversation_with_answer
      rsl = Comrade::Enlistee.find_by(name: 'rsl')
      rsl.update!(calibration: { 'break_down' => Comrade::Enlistee::NUDGE_THRESHOLD })

      get "/conversations/#{conversation.id}"
      expect(response.body).to include('Simpler by default?')

      delete '/calibration'
      get "/conversations/#{conversation.id}"
      expect(response.body).not_to include('Simpler by default?')
      expect(rsl.reload.prefs).to be_blank
    end

    it 'accepting writes the pref the injection reads and stops the offer' do
      conversation = conversation_with_answer
      rsl = Comrade::Enlistee.find_by(name: 'rsl')
      rsl.update!(calibration: { 'break_down' => Comrade::Enlistee::NUDGE_THRESHOLD })

      post '/calibration'

      expect(rsl.reload.prefs['keep_simple']).to eq(Comrade::Enlistee::KEEP_SIMPLE_LINE)
      expect(rsl.calibration['break_down']).to eq(0)

      get "/conversations/#{conversation.id}"
      expect(response.body).not_to include('Simpler by default?')
    end
  end

  describe 'the party line' do
    it 'saves the reader\'s line where the injection finds it' do
      enlist

      patch '/enlistment', params: { line: 'skip the caveats' }

      expect(Comrade::Enlistee.find_by(name: 'rsl').prefs['line']).to eq('skip the caveats')
    end

    it 'a blank save is the reset' do
      enlist
      Comrade::Enlistee.find_by(name: 'rsl').update!(prefs: { 'line' => 'skip the caveats' })

      patch '/enlistment', params: { line: '   ' }

      expect(Comrade::Enlistee.find_by(name: 'rsl').prefs).to be_blank
    end
  end
end