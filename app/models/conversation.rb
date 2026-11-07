# A chat session. Title is deliberately nullable: it is derived from the
# first message when the reply loop creates the conversation (2a) — the
# schema never guarantees a title.
# Lifecycle: live (archived_at nil) → archived (out of the recents, still
# readable) → destroyed (real destroy, messages cascade). Replying to an
# archived conversation resurrects it — sending a message is the strongest
# signal of life there is.
class Conversation < ApplicationRecord
  # The owner. Optional because nil is not owner-unknown: nil IS the
  # commune — the shared anon space a request without a token lives in.
  belongs_to :comrade,
    class_name: 'Comrade::Enlistee',
    optional: true,
    inverse_of: :conversations
  has_many :messages, -> { order(:id) }, dependent: :destroy

  scope :live, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }

  # The whole scoping model in one expression: a conversation is visible
  # to its enlistee alone; a nil enlistee sees exactly the commune's
  # stream. No special case, and only one commune is possible because
  # nil is nil.
  scope :for_enlistee, ->(enlistee) { where(comrade_id: enlistee&.id) }

  # Birth path for a conversation: the title is derived from the first
  # message at creation. The user message itself is persisted by
  # Comrade::Reply (its eager append is the 422 gate) — start! must not
  # double-write it. Nothing backfills the title later. The owner is
  # stamped from presence: nil on the commune. An image-only first turn
  # has no text to derive from, so it names itself.
  def self.start!(content:, images: [], enlistee: nil)
    create!(title: content.to_s.strip.gsub(/\s+/, ' ').slice(0, 50).presence || image_title(images), comrade: enlistee)
  end

  def self.image_title(images)
    images.size == 1 ? 'Image' : "#{ images.size } images"
  end

  def archived?
    archived_at.present?
  end

  def archive
    update!(archived_at: Time.current)
  end

  # Resurrection is deliberate lifecycle, not a bang-method misuse.
  def resurrect
    update!(archived_at: nil)
  end

  # The transcript is what Comrade::Reply sends to the API: messages in
  # conversation order, shaped per the OpenAI chat format. Assistant rows
  # that requested tools carry their tool_calls in tool_payload; tool rows
  # carry their result as content and their call id in tool_payload —
  # read_image's rows carry the full-resolution attachment copy as image
  # content. User rows with attachments ride the multimodal shape: text
  # first, then every attached image as a data URL read from disk at
  # request time.
  # `before:` scopes the transcript to rows earlier than the given row —
  # what a turn's request rode (everything the model had when it wrote
  # that answer, tool frames of the turn included).
  def to_transcript(before: nil)
    rows = before ? messages.where(id: ...before.id) : messages
    rows.map { |message| transcript_row(message) }
  end

  private

  def transcript_row(message)
    if message.role == 'assistant' && message.tool_payload&.key?('tool_calls')
      { role: 'assistant', content: message.content, tool_calls: message.tool_payload['tool_calls'] }
    elsif message.role == 'tool'
      tool_row(message)
    else
      { role: message.role, content: user_content(message) }
    end
  end

  def tool_row(message)
    row = { role: 'tool', tool_call_id: message.tool_payload['tool_call_id'] }
    image = message.tool_payload['image']
    return row.merge(content: message.content) unless image

    # Image parts inside a tool-role message are not guaranteed across
    # OpenAI-compatible endpoints — if the live endpoint rejects this
    # shape, the fallback is an image-bearing message right after the
    # tool call.
    row.merge(
      content: [
        { type: 'text', text: message.content },
        { type: 'image_url', image_url: { url: Comrade::ImageStore.data_url(image) } },
      ],
    )
  end

  def user_content(message)
    images = Array(message.images)
    return message.content if message.role != 'user' || images.blank?

    [
      type: 'text', text: [message.content, attachment_note(images)].compact.join("\n\n"),
    ] + images.map do |ref|
      { type: 'image_url', image_url: { url: Comrade::ImageStore.data_url(ref) } }
    end
  end

  # The model can only call read_image if it knows the attachment keys,
  # so every attachments-bearing turn names them — keys and downsampled
  # sizes, with the full-res copies called out as available.
  def attachment_note(images)
    lines = images.map do |ref|
      line = "- image #{ ref['key'] } (#{ ref['width'] }x#{ ref['height'] } #{ ref['content_type'] })"
      line + (ref['full'] ? ' — full-resolution copy available via read_image' : '')
    end
    "[attachments]\n#{ lines.join("\n") }"
  end
end
