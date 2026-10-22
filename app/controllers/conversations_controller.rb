class ConversationsController < ApplicationController
  include StreamsReply

  def index
    @conversations = Conversation.order(id: :desc).limit(20)
  end

  def show
    @conversation = Conversation.find(params[:id])
  end

  # Creates the conversation (title derived from the first message) and
  # streams the first reply: 201 with Location and X-Conversation-Id
  # headers, body being the SSE reply stream — one roundtrip for the
  # first exchange.
  def create
    conversation = Conversation.start!(content: params.require(:content))
    response.status = :created
    response.headers['Location'] = conversation_url(conversation)
    response.headers['X-Conversation-Id'] = conversation.id.to_s
    stream_reply(conversation)
  end
end
