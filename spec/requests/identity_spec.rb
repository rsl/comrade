# The identity gates: presence, claim, step-out, and the scoping rule.
# These are mechanics specs — gates, write paths, records — never page
# content. The invariants under test are the ones the design docs name:
# the token cookie is presence, names are addresses, nil owns the commune.
require 'rails_helper'

RSpec.describe 'Identity and scoping', type: :request do
  def enlist(name)
    post '/enlistment', params: { name: name }
    follow_redirect!
  end

  def step_out
    delete '/enlistment'
    follow_redirect!
  end

  def chip
    # The chip span carries the name (or "the commune") with the full
    # value mirrored into its aria-label — scoped by its truncate class,
    # since other aria-labels (font sizer) live on the page.
    response.body[/class="truncate text-sm text-neutral-300" aria-label="([^"]+)"/, 1]
  end

  def cookie_token
    # Rails deletes cookies by setting an empty value; the jar keeps the
    # empty string, so presence is what the app (and this spec) reads.
    cookies['comrade_token'].presence
  end

  describe 'enlisting' do
    it 'creates a comrade and remembers presence' do
      enlist 'rsl'

      expect(chip).to eq('rsl')
      expect(cookie_token).to be_present
      expect(Comrade::Enlistee.find_by(token: cookie_token).name).to eq('rsl')
    end

    it 'claims the existing comrade when the name exists — same row, same token' do
      enlist 'rsl'
      first_token = cookie_token

      step_out
      enlist 'rsl'

      expect(cookie_token).to eq(first_token)
      expect(Comrade::Enlistee.where(name: 'rsl').count).to eq(1)
    end

    it 'collapses whitespace in names' do
      enlist 'ann   lee'

      expect(Comrade::Enlistee.where(name: 'ann lee').count).to eq(1)
    end

    it 'refuses a blank name and stays on the commune' do
      enlist '   '

      expect(chip).to eq('the commune')
      expect(Comrade::Enlistee.count).to eq(0)
    end
  end

  describe 'stepping out' do
    it 'clears presence but keeps the comrade and its conversations' do
      enlist 'rsl'
      post '/conversations', params: { content: 'a question for rsl only' }
      conversation_id = response.headers['X-Conversation-Id'].to_i
      step_out

      expect(cookie_token).to be_nil
      expect(chip).to eq('the commune')
      expect(Comrade::Enlistee.find_by(name: 'rsl').conversations.ids).to include(conversation_id)
    end
  end

  describe 'the commune' do
    it 'gives anon conversations a nil owner' do
      post '/conversations', params: { content: 'a commune question' }

      expect(Conversation.order(:id).last.comrade_id).to be_nil
    end

    it 'hides other enlistees\' conversations from anon' do
      enlist 'brannon'
      post '/conversations', params: { content: 'brannon asks privately' }
      step_out

      get conversation_path(Conversation.order(:id).last)

      expect(response).to redirect_to(root_path)
    end
  end

  describe 'scoping' do
    it 'keeps one enlistee out of another\'s conversations — index and show' do
      enlist 'brannon'
      post '/conversations', params: { content: 'brannon asks privately' }
      brannons_id = response.headers['X-Conversation-Id'].to_i
      step_out
      enlist 'rsl'

      get '/conversations'
      expect(response.body).not_to include('brannon asks privately')

      get conversation_path(brannons_id)
      expect(response).to redirect_to(root_path)

      post "/conversations/#{brannons_id}/messages", params: { content: 'hijack attempt' }
      expect(response).to redirect_to(root_path)
    end

    it 'shows an enlistee their own conversations' do
      enlist 'rsl'
      post '/conversations', params: { content: 'rsl asks something' }

      get '/conversations'
      expect(response.body).to include('rsl asks something')
    end
  end

  describe 'the enlist gate' do
    it 'asks on every fresh load — no remembered dismissal' do
      get '/'
      expect(response.body).to include('Stay in the commune')

      get '/'
      expect(response.body).to include('Stay in the commune')
    end
  end
end