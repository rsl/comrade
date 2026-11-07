module Comrade
  class Reply
    # One reply's lane decision: which endpoint rides the turn — fast or
    # slow — and the model, key, and effort pin it carries. Built once
    # per reply from the turn's content: depth-words and pasted links
    # invoke the slow lane; the COMRADE_LLM_* env triples configure the
    # lanes, the legacy unsuffixed one the degrade contract.
    class TurnLane
      # Depth-mode invocation words, per config/comrade_prompt.md ("depth
      # is a mode the reader invokes with 'go deeper', 'find the study',
      # and words like that") — that file is the source of truth; keep
      # these mirroring it.
      DEPTH_TRIGGERS =
        /\b(go deeper|dive deeper|dig into|dig deeper|find the study|pull the study|walk me through|in detail)\b/i

      # A pasted link: "read this one" is an explicit pointer to a source.
      LINK = %r{\bhttps?://}i

      attr_reader :base_url, :model, :api_key, :effort, :kind

      def self.build(content)
        new(content)
      end

      def initialize(content)
        @content = content
        kind = ENV['COMRADE_LLM_FAST_BASE_URL'] ? default_kind : 'legacy'
        build_lane(kind)
        @effort = method("#{ kind }_effort").call
      end

      def default_kind
        invoked? && ENV['COMRADE_LLM_SLOW_BASE_URL'] ? 'slow' : 'fast'
      end

      private

      def build_lane(which)
        @kind = which
        @base_url = required_env(which, 'BASE_URL')
        @model = required_env(which, 'MODEL')
        @api_key = ENV[api_key_env(which)] || ENV['COMRADE_LLM_API_KEY']
      end

      # The legacy lane rides the unsuffixed names — the original
      # COMRADE_LLM_* triple, which is the degrade contract: one triple
      # configured, no fast lane, everything exactly as lane-less comrade
      # ran it.
      def env_name(which, suffix)
        return "COMRADE_LLM_#{ suffix }" if which == 'legacy'

        "COMRADE_LLM_#{ which.upcase }_#{ suffix }"
      end

      def api_key_env(which)
        env_name(which, 'API_KEY')
      end

      def required_env(which, suffix)
        key = env_name(which, suffix)
        value = ENV[key]
        return value if value.present?

        raise UpstreamError, "#{ key } is not set"
      end

      def invoked?
        @content.match?(DEPTH_TRIGGERS) || @content.match?(LINK)
      end

      def words?
        @content.match?(DEPTH_TRIGGERS)
      end

      # Depth mode: the reader invoked it in words, so think hard; a
      # pasted link is explicit but skips the pre-deliberation budget.
      # COMRADE_LLM_SLOW_EFFORT: 'adaptive' (also unset) encodes exactly
      # that word/link split; 'low'/'high' pin it; anything unknown fails
      # loudly — misconfiguring silently is worse than erroring.
      def slow_effort
        pin('COMRADE_LLM_SLOW_EFFORT') || slow_adaptive
      end

      def slow_adaptive
        words? ? 'high' : 'low'
      end

      # Fast lane effort: the endpoint's own chat template governs
      # (Flash-Next behaves — its defaults are what the bench praised),
      # so unset, empty and 'adaptive' all send no field. 'low'/'high'
      # pin it; unknown fails loudly.
      def fast_effort
        pin('COMRADE_LLM_FAST_EFFORT')
      end

      # The lane pin: 'low'/'high' → the value; unset, empty and
      # 'adaptive' → nil (caller decides); anything unknown raises.
      def pin(env_key)
        value = ENV.fetch(env_key, '').presence
        return value if value.in?(%w[low high])

        unless value.blank? || value == 'adaptive'
          raise UpstreamError, "#{ env_key }: unknown value \"#{ value }\"; use low, high, adaptive, or unset"
        end

        nil
      end

      # The legacy lane's own contract: COMRADE_LLM_REASONING_EFFORT with
      # 'adaptive' treating word and link invocation alike — this is the
      # single-endpoint behavior pre-lanes, kept for unchanged setups.
      def legacy_effort
        value = ENV.fetch('COMRADE_LLM_REASONING_EFFORT', '')
        case value
        when 'adaptive'
          'high' if invoked?
        when 'low', 'high'
          value
        end
      end
    end
  end
end
