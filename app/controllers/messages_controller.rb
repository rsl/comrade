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
end
