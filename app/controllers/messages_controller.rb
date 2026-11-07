class MessagesController < ApplicationController
  include StreamsReply

  # Appends the user message to the conversation and streams the
  # assistant's reply for it. Location lets a first-exchange client find
  # the conversation's permanent address after the stream. The find is
  # scoped: another enlistee's conversation is simply not found.
  def create
    conversation = Conversation.for_enlistee(current_enlistee).find(params[:conversation_id])
    response.headers['Location'] = conversation_url(conversation)
    stream_reply(conversation)
  end

  # The prompt inspector: the wire request an answer's turn rode,
  # rebuilt from the transcript plus the current prompt file and prefs.
  def prompt
    @conversation = Conversation.for_enlistee(current_enlistee).find(params[:conversation_id])
    message = @conversation.messages.find(params[:id])
    raise ActiveRecord::RecordNotFound unless message.role == 'assistant'

    @request = rebuilt_wire_request(message)
  end

  private

  # The inspector rebuilds the request the turn rode: the lane recorded
  # in the row's stats (model, effort, search mode) over the transcript
  # up to the answer row, the config pieces read as they are now.
  def rebuilt_wire_request(message)
    stats = message.stats || {}
    reply = Comrade::Reply.new(conversation: @conversation, content: '')
    reply.rebuilt_request(upto: message, model: stats['model'], effort: stats['effort'], mode: stats['mode'])
  end
end
