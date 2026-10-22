# One turn in a conversation. Role is the OpenAI chat vocabulary —
# user / assistant / tool — enforced here so the transcript is always
# wire-shaped. The system prompt is config, never a row. Content presence
# is a user-message guarantee: assistant tool_calls rows (2b) legitimately
# carry null content.
class Message < ApplicationRecord
  belongs_to :conversation

  validates :role, inclusion: { in: %w[user assistant tool] }
  validates :content, presence: true, if: -> { role == 'user' }
end
