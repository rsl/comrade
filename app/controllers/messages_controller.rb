class MessagesController < ApplicationController
  include StreamsReply

  # Appends the user message to the conversation and streams the
  # assistant's reply for it. Location lets a first-exchange client find
  # the conversation's permanent address after the stream.
  def create
    conversation = Conversation.find(params[:conversation_id])
    response.headers['Location'] = conversation_url(conversation)
    stream_reply(conversation)
  end
end
