# A chat session. Title is deliberately nullable: it is derived from the
# first message when the reply loop creates the conversation (2a) — the
# schema never guarantees a title.
class Conversation < ApplicationRecord
  has_many :messages, -> { order(:id) }, dependent: :destroy

  # Birth path for a conversation: the title is derived from the first
  # message at creation. The user message itself is persisted by
  # Comrade::Reply (its eager append is the 422 gate) — start! must not
  # double-write it. Nothing backfills the title later.
  def self.start!(content:)
    create!(title: content.strip.gsub(/\s+/, ' ').slice(0, 50))
  end

  # The transcript is what Comrade::Reply sends to the API: messages in
  # conversation order, shaped per the OpenAI chat format. Tool-message
  # shape (tool_call_id / name) arrives with 2b, when the loop consumes it.
  def to_transcript
    messages.map { |message| { role: message.role, content: message.content } }
  end
end
