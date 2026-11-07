# SSE transport for Comrade::Reply: shapes deltas into event lines and
# hands Puma a lazy enumerator body — streaming without ActionController::Live
# and its per-request thread; Rails' executor stays active until the body
# is fully consumed, so message writes inside the stream are safe. These
# endpoints carry no session to forge, and the only thing a cross-site POST
# could spend is a few local model tokens.
module StreamsReply
  extend ActiveSupport::Concern

  included do
    skip_forgery_protection

    rescue_from ActiveRecord::RecordInvalid do |error|
      render json: { errors: error.record.errors.full_messages }, status: :unprocessable_content
    end
    # A staged attachment the store won't take (wrong type, empty, over
    # the cap) is the same kind of answer as a validation failure — the
    # turn never starts.
    rescue_from Comrade::ImageStore::Rejected do |error|
      render json: { errors: [error.message] }, status: :unprocessable_content
    end
  end

  private

  # The "break it down" turn is the calibration signal: the canned text
  # (Comrade::Enlistee::BREAK_DOWN_TURN) is app-controlled, so matching
  # on it counts clicks without extra plumbing — and a reader typing it
  # naturally counts too, which is semantically right.
  def count_calibration_signal
    current_enlistee&.count_break_down! if params[:content].to_s.strip == Comrade::Enlistee::BREAK_DOWN_TURN
  end

  def stream_reply(conversation)
    count_calibration_signal
    set_stream_headers
    content = params.require(:content)
    # The reader's search-mode switch: only a known mode survives —
    # anything else is the default turn.
    mode = params[:mode].to_s.in?(%w[images]) ? 'images' : nil
    # :reek:ControlParameter — the request picks the entry point; that is
    # the controller's job.
    reply = if ActiveModel::Type::Boolean.new.cast(params[:retry])
      retry_reply(conversation, content, mode)
    else
      Comrade::Reply.call(**reply_options(conversation, content, mode))
    end
    self.response_body = reply_enumerator(reply)
  end

  # A retry re-sends a turn the client believes failed — but the client
  # can't tell a connection that died after the server finished from a
  # server that died mid-answer. The database can, so the retry is a
  # three-way call:
  #   - the turn was never stored (the request was lost before
  #     persistence): the normal path, which persists the user message
  #     before streaming — the retry repairs itself instead of answering
  #     a question the transcript will never show;
  #   - stored and already answered (an assistant row with content after
  #     it): a duplicate no-op — the client discards its empty retry turn
  #     and a fresh page visits the true transcript;
  #   - stored, unanswered (only tool rows behind it): the genuine retry —
  #     call_retry, user persistence skipped.
  def reply_options(conversation, content, mode)
    {
      conversation: conversation,
      content: content,
      interrupted: params[:interrupted],
      mode: mode,
      images: Array(params[:images]),
    }
  end

  def retry_reply(conversation, content, mode)
    case retry_case(conversation, content)
    when :missing
      Comrade::Reply.call(**reply_options(conversation, content, mode))
    when :answered
      duplicate_stream
    else
      # call_retry skips user persistence — the refs live on the row, so
      # the re-sent staging payload has nothing to do there.
      Comrade::Reply.call_retry(**reply_options(conversation, content, mode).except(:images))
    end
  end

  # Where the retried turn stands, from the transcript's own record.
  # Safe navigation carries the no-user-message case, and an image-only
  # turn's nil content reads as empty — a staged-images retry matches
  # its own row instead of re-persisting a duplicate.
  def retry_case(conversation, content)
    last_user = conversation.messages.where(role: 'user').last
    return :missing if (last_user&.content || '').strip != content.to_s.strip

    answered = conversation.messages.where(role: 'assistant')
      .where('id > ? AND content IS NOT NULL', last_user.id).exists?
    answered ? :answered : :pending
  end

  # The already-answered retry: no new work, just the events the client
  # needs to treat the turn as complete.
  def duplicate_stream
    Enumerator.new do |yielder|
      yielder << "data: #{ { type: 'duplicate' }.to_json }\n\n"
      yielder << "data: [DONE]\n\n"
    end
  end

  def set_stream_headers
    headers['Content-Type'] = 'text/event-stream'
    headers['Cache-Control'] = 'no-cache'
    headers['X-Accel-Buffering'] = 'no'
  end

  def reply_enumerator(reply)
    Enumerator.new do |yielder|
      reply.each { |delta| yielder << "data: #{ delta.to_json }\n\n" }
      yielder << "data: [DONE]\n\n"
    rescue StandardError => error
      stream_failure(yielder, error)
    end
  end

  # The status is already 200 and streaming, so a failure travels as an
  # event; the reader renders it into the retry line. Any exception the
  # reply loop raises rides this — an unexpected one used to kill the
  # stream outright, Puma logging it as a client read error the tab
  # never saw (2026-11-01: a fetch_page contract miss died this way
  # three turns running). Logging server-side too, with the raise site —
  # the retry line dies with the tab, the log doesn't (the 2026-10-24
  # diagnosis was archaeology without this).
  def stream_failure(yielder, error)
    Rails.logger.error("[reply] stream failed: #{ error.class }: #{ error.message } — #{ error.backtrace&.first }")
    yielder << "data: #{ { type: 'error', message: error.message }.to_json }\n\n"
    yielder << "data: [DONE]\n\n"
  end
end
