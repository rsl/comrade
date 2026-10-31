class ConversationsController < ApplicationController
  include StreamsReply

  def index
    # The chat surface at root; the conversation listings — the full
    # Recent page and the archives — are index with a mode param: one
    # listing shape, two scopes. No query on the plain chat root; the
    # sidebar runs its own.
    @archived = params[:archived].present?
    @all = params[:all].present?
    @conversations =
      if @archived
        Conversation.archived.for_enlistee(current_enlistee).order(created_at: :desc)
      elsif @all
        Conversation.live.for_enlistee(current_enlistee).order(created_at: :desc)
      end
  end

  def show
    @conversation = scoped_conversations.find(params[:id])
  end

  # Archive: remove the row in place so list state survives multi-archive.
  # Two targets: the sidebar's row (dom_id) and the listing page's row
  # (listing_ prefix) — on any given page one of the two is absent, and a
  # remove with no target no-ops silently. If the client doesn't speak
  # Turbo Stream, or the archived conversation is the one on screen (the
  # page under you would yank away), fall back to a redirect.
  def archive
    conversation = scoped_conversations.find(params[:id])
    conversation.archive
    if remove_row_in_place?(conversation)
      render turbo_stream: turbo_stream.remove(conversation)
        .concat(turbo_stream.remove("listing_#{ dom_id(conversation) }"))
    else
      redirect_back_or_to root_path
    end
  end

  def unarchive
    scoped_conversations.find(params[:id]).resurrect
    redirect_back_or_to root_path
  end

  # Destroyed for real: messages cascade with it. Reachable for live and
  # archived conversations alike — the confirm dialog is the guard, not a
  # two-step path through the archives.
  def destroy
    conversation = scoped_conversations.find(params[:id])
    conversation.destroy!
    redirect_back_or_to all_conversations_path
  end

  # Creates the conversation (title derived from the first message) and
  # streams the first reply: 201 with Location and X-Conversation-Id
  # headers, body being the SSE reply stream — one roundtrip for the
  # first exchange. The owner is stamped from presence: nil on the
  # commune, so anon asks land in the shared stream.
  def create
    conversation = Conversation.start!(content: params.require(:content), enlistee: current_enlistee)
    response.status = :created
    response.headers['Location'] = conversation_url(conversation)
    response.headers['X-Conversation-Id'] = conversation.id.to_s
    stream_reply(conversation)
  end

  private

  # In-place Turbo Stream removal only when the client speaks Turbo Stream
  # and isn't viewing the archived conversation itself — archiving the page
  # under you needs the redirect home instead.
  def remove_row_in_place?(conversation)
    request.format.turbo_stream? && !viewing_conversation?(conversation)
  end

  def viewing_conversation?(conversation)
    request.referer && URI.parse(request.referer).path == conversation_path(conversation)
  end

  def scoped_conversations
    Conversation.for_enlistee(current_enlistee)
  end
end
