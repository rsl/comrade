# The search-engine door: an OpenSearch client hands the query over as a
# plain GET — #show answers it by booting the turn as a pending one (the
# conversation and its user row exist, the reply does not yet) and landing
# on the conversation page, where the stream reader auto-resumes through
# the normal retry path. No reply call here: the browser's GET wants a
# page, not an event stream, and the retry machinery already knows how to
# pick a stored-but-unanswered turn back up idempotently.
class SearchesController < ApplicationController
  def show
    q = params[:q].to_s.strip
    return redirect_to root_path if q.blank?

    conversation = Conversation.start!(content: q, enlistee: current_enlistee)
    conversation.messages.create!(role: 'user', content: q)
    redirect_to conversation_path(conversation)
  end

  # The description document behind the layout's link rel="search": this
  # is what makes Firefox's address-bar magnifier offer "Add Comrade".
  # The URL helper fills the host from the request, so whatever name a
  # device reached the app by is the one it registers.
  def opensearch
    response.headers['Content-Type'] = 'application/opensearchdescription+xml'
    render :opensearch
  end
end
