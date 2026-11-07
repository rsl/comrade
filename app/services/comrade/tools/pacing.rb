module Comrade
  module Tools
    # One pace floor shared by every SearXNG-backed tool (web search,
    # image search): both ride the same SearXNG, whose upstream engines
    # throttle bursts hard — a fast model firing several queries a second
    # gets everything suspended, which reads to it as "no results" and
    # invites more searching. Process-wide state, one queue for all.
    module Pacing
      # Seconds between upstream queries.
      MIN_INTERVAL = 1.0

      def self.pace
        @lock ||= Mutex.new
        @lock.synchronize do
          @last_query ||= Time.at(0).utc
          gap = Time.now.utc - @last_query
          sleep(MIN_INTERVAL - gap) if gap < MIN_INTERVAL
          @last_query = Time.now.utc
        end
      end
    end
  end
end
