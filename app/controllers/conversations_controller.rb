class ConversationsController < ApplicationController
  include StreamsReply

  def index
    @archived = params[:archived].present?
    @conversations = if @archived
      Conversation.archived.order(:archived_at)
    else
      Conversation.live.order(id: :desc).limit(20)
    end
  end

  # The archive listing — read-only titles, the only door to destroy.
  def archived
    @archived = true
    @conversations = Conversation.archived.order(:archived_at)
  end

  def show
    @conversation = Conversation.find(params[:id])
  end

  # Archive: remove the sidebar row in place so edit mode survives
  # multi-archive. If the archived conversation is the one on screen (or the
  # client doesn't speak Turbo Stream), fall back to a redirect.
  def archive
    conversation = Conversation.find(params[:id])
    conversation.archive
    viewing_it = request.referer && URI.parse(request.referer).path == conversation_path(conversation)
    if request.format.turbo_stream? && !viewing_it
      render turbo_stream: turbo_stream.remove(conversation)
    else
      redirect_back_or_to root_path
    end
  end

  def unarchive
    Conversation.find(params[:id]).resurrect
    redirect_back_or_to root_path
  end

  # Destroyed for real: messages cascade with it. Only reachable for
  # archived conversations — destruction is always the second step.
  def destroy
    conversation = Conversation.archived.find(params[:id])
    conversation.destroy!
    redirect_to archived_conversations_path
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
