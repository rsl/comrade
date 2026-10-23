module Comrade
  class Reply
    # The LLM endpoint is unreachable, erroring, or misconfigured —
    # anything upstream the reply loop can't recover from.
    class UpstreamError < StandardError; end
  end
end
