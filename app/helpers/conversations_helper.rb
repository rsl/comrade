module ConversationsHelper
  # The chat surface: transcript plus query form under one Stimulus root,
  # so the stream-reader controller can reach both. `fresh` marks the
  # index form — its first exchange streams in place, then Turbo visits
  # the conversation's permanent address.
  def chat_surface(endpoint:, fresh:, conversation: nil, messages: [])
    render 'chat', endpoint:, fresh:, conversation:, messages:
  end

  # The provenance segment of the answer's footer line: which lane wrote
  # it, the model on it, and the turn's timings — from the row's stats
  # jsonb. Empty when the row carries none (steered partials, older
  # answers). Byte-identical with the stream reader's statsSegment; the
  # post-first-reply Turbo.visit swaps one for the other.
  def stats_segment(message)
    stats = message.stats
    return '' if stats.blank?

    segments = { lane: "#{ stats['lane'] } lane",
                 model: stats['model'],
                 effort: "effort #{ stats['effort'] }",
                 first_token_ms: "first token #{ stat_seconds(stats['first_token_ms']) }",
                 total_ms: "total #{ stat_seconds(stats['total_ms']) }", }
    rendered = segments.filter_map { |key, text| text if stats[key.to_s] }
    rendered.empty? ? '' : " · #{ rendered.join(' · ') }"
  end

  def stat_seconds(milliseconds)
    "#{ (milliseconds.to_f / 1000).round(1) }s"
  end

  # The prompt-inspector link riding the stats segment: every answer
  # carrying stats gets one. Byte-twin of the stream reader's promptLink —
  # the row id arrives on the stats event there.
  def prompt_link(message)
    return '' if message.stats.blank?

    path = prompt_conversation_message_path(message.conversation_id, message)
    # safe_join, not string interpolation: interpolation strips link_to's
    # safety flag and ERB would escape the anchor into visible text.
    safe_join([' · ', link_to('prompt', path, class: 'prompt-link cursor-pointer underline hover:text-neutral-300')])
  end

  # The id of the conversation's most recent answer carrying stats — the
  # only turn whose foreman's status line has a target. Steered partials
  # persist stats-less, so the line lands on the last completed answer.
  def turn_status_id(messages)
    messages.reverse.detect { |turn| turn.role == 'assistant' && turn.stats.present? }&.id
  end

  # The foreman's status line and its log, on the latest answer carrying
  # stats — the reload twin of the render the stream reader leaves behind
  # at completion: a quiet line (lane, the turn's total) that clicks open
  # the timestamped log the server accumulated during the turn.
  # Byte-identical with the stream reader's completeTurnStatus.
  def turn_status(message)
    stats = message.stats
    dot = tag.span(class: 'live-dot inline-block h-1.5 w-1.5 rounded-full bg-soviet')
    text = tag.span(turn_status_text(stats), class: 'turn-status-text grow')
    line = tag.p(dot + text,
      class: 'turn-status flex cursor-pointer items-center gap-2 text-xs text-neutral-500',
      data: { action: 'click->stream-reader#toggleTurnLog' },)
    log = tag.pre(stats['log'].join("\n"),
      class: 'turn-log hidden mb-2 whitespace-pre-wrap border-l-2 border-soviet/40 ' \
             'pl-2 text-xs leading-relaxed text-neutral-500',)
    line + log
  end

  # The archive row's label: the conversation's whole first line — the
  # prompt as asked, not the 50-char title. First non-blank line of the
  # first user turn; the title stands in when the row has none.
  def archive_line(conversation)
    content = conversation.messages.where(role: 'user').order(:id).pick(:content)
    line = content.to_s.lines.map(&:strip).detect(&:present?)
    line.presence || conversation.title.presence || '(Untitled)'
  end

  def turn_status_text(stats)
    [stats['lane'] && "#{ stats['lane'] } lane", turn_clock(stats['total_ms'])].compact.join(' · ')
  end

  def turn_clock(milliseconds)
    format('%<m>d:%<ss>02d', m: milliseconds.to_i / 60_000, ss: milliseconds.to_i / 1000 % 60)
  end

  def message_turn(message, tool_notes:, double_check:, break_down:, turn_log: false)
    render 'message', message:, tool_notes:, double_check:, break_down:, turn_log:
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

  # The conversation listings' buckets, in encounter order over the
  # created_at-desc list: Today, Yesterday, then Monday-anchored weeks
  # ("Week of Oct 26" — the current week included; only Today and
  # Yesterday get named). When the reader asked is the grouping the page
  # shows.
  def time_groups(conversations)
    groups = {}
    conversations.each do |conversation|
      label = time_bucket(conversation.created_at.to_date)
      (groups[label] ||= []) << conversation
    end
    groups
  end

  def time_bucket(date)
    today = Date.current
    return 'Today' if date == today
    return 'Yesterday' if date == today - 1

    "Week of #{ date.beginning_of_week.strftime('%b %-d') }"
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
