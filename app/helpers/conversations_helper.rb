module ConversationsHelper
  # The chat surface: transcript plus query form under one Stimulus root,
  # so the stream-reader controller can reach both. `fresh` marks the
  # index form — its first exchange streams in place, then Turbo visits
  # the conversation's permanent address.
  def chat_surface(endpoint:, fresh:, conversation: nil, messages: [])
    render 'chat', endpoint:, fresh:, conversation:, messages:
  end

  def message_turn(message)
    render 'message', message:
  end

  def recent_conversations(conversations)
    render 'recent', conversations:
  end

  # Source links joined with separators; titles fall back to the URL.
  def citation_links(citations)
    links = citations.map do |citation|
      link_to citation['title'] || citation['url'],
        citation['url'],
        target: '_blank',
        rel: 'noopener',
        class: 'underline hover:text-neutral-300'
    end
    safe_join(links, ' · ')
  end
end
