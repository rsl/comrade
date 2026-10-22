# A chat session. Title is deliberately nullable: it is derived from the
# first message when the reply loop creates the conversation (2a) — the
# schema never guarantees a title.
class Conversation < ApplicationRecord
  has_many :messages, -> { order(:id) }, dependent: :destroy

  # Birth path for a conversation: the title is derived from the first
  # message at creation. Nothing backfills it later.
  def self.start!(content:)
    create!(title: content.strip.gsub(/\s+/, ' ').slice(0, 50)).tap do |conversation|
      conversation.messages.create!(role: 'user', content: content)
    end
  end

  # The transcript is what Comrade::Reply sends to the API: messages in
  # conversation order, shaped per the OpenAI chat format. Tool-message
  # shape (tool_call_id / name) arrives with 2b, when the loop consumes it.
  def to_transcript
    messages.map { |message| { role: message.role, content: message.content } }
  end
end
