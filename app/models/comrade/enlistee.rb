module Comrade
  # One of the household: a named identity. The token remembers, nothing
  # verifies — the tailnet is the perimeter, the cookie only remembers.
  # The model nests because the Comrade:: namespace belongs to the
  # services (Comrade::Reply and friends).
  class Enlistee < ApplicationRecord
    self.table_name = 'comrades'

    # The canned simplification turn the answer's "break it down" link
    # submits — the stream reader holds the same literal, and the count
    # hook matches on it. Keep the two in lockstep.
    BREAK_DOWN_TURN = 'break that down — plainer, smaller pieces, same ground.'
    # The pref line a confirmed "keep it simpler" offer writes.
    KEEP_SIMPLE_LINE = 'keep it simple — plainer, smaller pieces, plain words first.'
    NUDGE_THRESHOLD = 3

    has_secure_token :token
    has_many :conversations,
      foreign_key: :comrade_id,
      inverse_of: :comrade,
      dependent: :nullify

    validates :name, presence: true, uniqueness: true, length: { maximum: 40 }

    # Claim or enlist: an existing name claims its comrade, a new one
    # joins. Whitespace collapsed so a doubled space is still one address.
    def self.enlist!(name)
      normalized = name.strip.gsub(/\s+/, ' ')
      find_or_create_by!(name: normalized)
    end

    # Calibration is telemetry only the code reads — the model never sees
    # it (prefs and calibration are separate blobs so the border is a
    # column boundary).
    def count_break_down!
      # jsonb row data — string keys are the storage contract.
      # rubocop:disable-next Style/StringHashKeys
      counts = (calibration || {}).merge('break_down' => (calibration || {})['break_down'].to_i + 1)
      update!(calibration: counts)
    end

    # One quiet offer, once: repeated break-it-downs propose making it the
    # default. Silence counts as an answer — it never asks again.
    def offer_keep_simple?
      state = calibration || {}
      state['break_down'].to_i >= NUDGE_THRESHOLD && !state['break_down_nudged'] &&
        (prefs || {})['keep_simple'].blank?
    end

    def accept_keep_simple!
      # jsonb row data — string keys are the storage contract.
      # rubocop:disable-next Style/StringHashKeys
      update!(prefs: (prefs || {}).merge('keep_simple' => KEEP_SIMPLE_LINE),
        calibration: (calibration || {}).merge('break_down' => 0, 'break_down_nudged' => true),)
    end

    def decline_keep_simple!
      # jsonb row data — string keys are the storage contract.
      # rubocop:disable-next Style/StringHashKeys
      update!(calibration: (calibration || {}).merge('break_down_nudged' => true))
    end
  end
end
