module Comrade
  # One of the household: a named identity. The token remembers, nothing
  # verifies — the tailnet is the perimeter, the cookie only remembers.
  # The model nests because the Comrade:: namespace belongs to the
  # services (Comrade::Reply and friends).
  class Enlistee < ApplicationRecord
    self.table_name = 'comrades'

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
  end
end
