module ConversationsHelper
  # The chat surface: transcript plus query form under one Stimulus root,
  # so the stream-reader controller can reach both. `fresh` marks the
  # index form — its first exchange streams in place, then Turbo visits
  # the conversation's permanent address.
  def chat_surface(endpoint:, fresh:, conversation: nil, messages: [])
    render 'chat', endpoint:, fresh:, conversation:, messages:
  end

  # The provenance segment of the answer's footer line: the turn's total
  # time — from the row's stats jsonb. On the latest stats answer it is
  # the click target that toggles the foreman's log; on older answers
  # plain text. Empty when the row carries no stats (steered partials,
  # older answers without). Byte-identical with the stream reader's
  # statsSegment; the post-first-reply Turbo.visit swaps one for the other.
  def stats_segment(message, clickable: false)
    stats = message.stats
    return '' if stats.blank? || stats['total_ms'].blank?

    total = "total #{ stat_seconds(stats['total_ms']) }"
    inner =
      if clickable
        tag.span(
          total,
          class: 'cursor-pointer hover:text-neutral-300',
          data: { action: 'click->stream-reader#toggleTurnLog' },
        )
      else
        total
      end
    safe_join([' · ', inner])
  end

  def stat_seconds(milliseconds)
    "#{ (milliseconds.to_f / 1000).round(1) }s"
  end

  # The id of the conversation's most recent answer carrying stats — the
  # only turn whose foreman's log rides the action line. Steered partials
  # persist stats-less, so it lands on the last completed answer.
  def turn_status_id(messages)
    messages.reverse.detect { |turn| turn.role == 'assistant' && turn.stats.present? }&.id
  end

  # The foreman's dot, stood: the merged action line's marker that this
  # turn carries a log. Byte-twin of the stream reader's completion markup.
  def standing_dot
    tag.span(class: 'live-dot mr-2 inline-block h-1.5 w-1.5 rounded-full bg-soviet')
  end

  # The foreman's timestamped log, collapsed under the merged action line
  # and opened from the total time. Empty when the turn kept no log.
  # Byte-twin of the stream reader's appendTurnLogPre.
  def turn_log_pre(message)
    return '' if message.stats['log'].blank?

    tag.pre(message.stats['log'].join("\n"),
      class: 'turn-log hidden mt-2 whitespace-pre-wrap border-l-2 border-soviet/40 ' \
             'pl-2 text-xs leading-relaxed text-neutral-500',)
  end

  # The archive row's label: the conversation's whole first line — the
  # prompt as asked, not the 50-char title. First non-blank line of the
  # first user turn; the title stands in when the row has none.
  def archive_line(conversation)
    content = conversation.messages.where(role: 'user').order(:id).pick(:content)
    line = content.to_s.lines.map(&:strip).detect(&:present?)
    line.presence || conversation.title.presence || '(Untitled)'
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
    case tool.tool_name
    when 'web_search' then "searched for #{ tool.tool_payload['arguments']['query'] }"
    when 'image_search' then "searched images for #{ tool.tool_payload['arguments']['query'] }"
    else "fetched #{ tool.tool_payload['arguments']['url'] }"
    end
  end

  # The thumbnail strip an image_search row found: proxied thumbs
  # (comrade serves the bytes), tap opens the full image in the
  # lightbox. Sits under the turn's chips, ahead of the answer. The raw
  # source urls live on the row's payload; the proxy derives both
  # addresses.
  def image_strip(tool)
    buttons = tool.tool_payload['images'].to_a.map { |image| strip_button(image) }
    # rubocop:disable-next Rails/OutputSafety — strip_button escapes every
    # interpolated piece; the wrapper literals are static.
    %Q(<div class="image-strip mt-1 mb-3 flex gap-2 overflow-x-auto">#{ buttons.join }</div>).html_safe
  end

  # One thumbnail button, built as raw markup so the render stays
  # byte-identical with the stream reader's imageStripHtml — the
  # post-first-reply Turbo.visit swaps one for the other. Attributes are
  # hand-escaped: titles are model-adjacent text, never trusted.
  # data-thumb-url rides for the lightbox's fallback: when the full-size
  # source can't be served, the known-good thumbnail shows instead.
  def strip_button(image)
    title = html_escape(image['title'].to_s)
    full = html_escape(Comrade::ImageProxy.url_for(image['src']))
    thumb = html_escape(Comrade::ImageProxy.url_for(image['thumbnail']))
    [
      '<button type="button" class="shrink-0 cursor-pointer" data-action="click->lightbox#open" ',
      %Q(data-full-url="#{ full }" data-thumb-url="#{ thumb }" data-caption="#{ title }">),
      %Q(<img src="#{ thumb }" alt="#{ title }" loading="lazy" class="h-24 w-auto rounded">),
      '</button>',
    ].join
  end
end
