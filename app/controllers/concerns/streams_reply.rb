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
    # :reek:ControlParameter — the request picks the entry point; that is
    # the controller's job.
    reply = if ActiveModel::Type::Boolean.new.cast(params[:retry])
      Comrade::Reply.call_retry(conversation: conversation,
        content: params.require(:content),
        interrupted: params[:interrupted],)
    else
      Comrade::Reply.call(conversation: conversation,
        content: params.require(:content),
        interrupted: params[:interrupted],)
    end
    self.response_body = reply_enumerator(reply)
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
    rescue Comrade::Reply::UpstreamError => error
      # The status is already 200 and streaming, so the failure travels as
      # an event; the reader renders it into the retry line. Logging it
      # server-side too — the retry line dies with the tab, the log
      # doesn't (the 2026-10-24 diagnosis was archaeology without this).
      Rails.logger.error("[reply] upstream failure: #{ error.message }")
      yielder << "data: #{ { type: 'error', message: error.message }.to_json }\n\n"
      yielder << "data: [DONE]\n\n"
    end
  end
end
