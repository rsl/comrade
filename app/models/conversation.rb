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
  # conversation order, shaped per the OpenAI chat format. Assistant rows
  # that requested tools carry their tool_calls in tool_payload; tool rows
  # carry their result as content and their call id in tool_payload.
  def to_transcript
    messages.map do |message|
      if message.role == 'assistant' && message.tool_payload&.key?('tool_calls')
        { role: 'assistant', content: message.content, tool_calls: message.tool_payload['tool_calls'] }
      elsif message.role == 'tool'
        { role: 'tool', tool_call_id: message.tool_payload['tool_call_id'], content: message.content }
      else
        { role: message.role, content: message.content }
      end
    end
  end
end
