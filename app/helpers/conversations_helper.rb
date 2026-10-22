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
end
