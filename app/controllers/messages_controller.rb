class MessagesController < ApplicationController
  include StreamsReply

  # Appends the user message to the conversation and streams the
  # assistant's reply for it.
  def create
    conversation = Conversation.find(params[:conversation_id])
    stream_reply(conversation)
  end
end
