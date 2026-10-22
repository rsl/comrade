# One turn in a conversation. Role is the OpenAI chat vocabulary —
# user / assistant / tool — enforced here so the transcript is always
# wire-shaped. The system prompt is config, never a row.
class Message < ApplicationRecord
  belongs_to :conversation

  validates :role, inclusion: { in: %w[user assistant tool] }
end
