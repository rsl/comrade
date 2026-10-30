module ConversationsHelper
  # The chat surface: transcript plus query form under one Stimulus root,
  # so the stream-reader controller can reach both. `fresh` marks the
  # index form — its first exchange streams in place, then Turbo visits
  # the conversation's permanent address.
  def chat_surface(endpoint:, fresh:, conversation: nil, messages: [])
    render 'chat', endpoint:, fresh:, conversation:, messages:
  end

  def message_turn(message, tool_notes:, double_check:, break_down:)
    render 'message', message:, tool_notes:, double_check:, break_down:
  end

  # The id of the conversation's most recent memory answer - the only turn
  # whose "double check" link has an unambiguous target. On older turns the
  # canned verification question would land after the full transcript and
  # point at whatever answer came last, so the link renders on the latest
  # memory answer alone.
  def double_check_id(messages)
    latest = messages.reverse.detect do |turn|
      turn.role == 'assistant' && turn.citations.blank? && turn.tool_payload.blank?
    end
    latest&.id
  end

  # The id of the conversation's most recent answer with content — the
  # only turn whose "break it down" link has a target ("break that down"
  # is conversation-wide; two links would be two guesses). Rides search
  # answers too: density isn't a memory-answer disease.
  def break_down_id(messages)
    messages.reverse.detect { |turn| turn.role == 'assistant' && turn.content.present? }&.id
  end

  # One transcript turn: a message plus the tool chips that answer into
  # it. Consecutive tool rows group into the following non-tool message; a
  # tool_calls frame with no spoken content renders nothing and must not
  # flush the chips pending for the answering turn. Tools trailing with no
  # answer become their own bare turns (the partial's stray-row branch
  # renders them).
  # rubocop:disable-next Metrics/MethodLength — one coherent scan; splitting
  # it would hide the grouping shape behind indirection.
  # :reek:TooManyStatements — the grouping walk is one coherent scan.
  def grouped_turns(messages)
    turns = []
    pending = []
    messages.each do |message|
      if message.role == 'tool'
        pending << message
      elsif message.role == 'assistant' && message.tool_payload.present? && message.content.blank?
        # Nothing spoken: render nothing, keep chips pending.
      else
        turns << [message, pending]
        pending = []
      end
    end
    pending.each { |tool| turns << [tool, []] }
    turns
  end

  # The quiet chip text for a tool row: what comrade did, in prose.
  def tool_note(tool)
    if tool.tool_name == 'web_search'
      "searched for #{ tool.tool_payload['arguments']['query'] }"
    else
      "fetched #{ tool.tool_payload['arguments']['url'] }"
    end
  end
end
