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

  def stream_reply(conversation)
    set_stream_headers
    reply = Comrade::Reply.call(conversation: conversation, content: params.require(:content))
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
    end
  end
end
