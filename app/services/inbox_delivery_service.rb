class InboxDeliveryService
  def self.deliver(recipient:, subject:, body_html:, body_text: nil, message_type: "notification",
                   sender: nil, email_template: nil, reference: nil, metadata: {})
    message = InboxMessage.create!(
      recipient: recipient,
      sender: sender,
      subject: subject,
      body_html: body_html,
      body_text: body_text.presence || ActionView::Base.full_sanitizer.sanitize(body_html),
      message_type: message_type,
      email_template: email_template,
      reference_type: reference&.class&.name,
      reference_id: reference&.id,
      metadata: metadata
    )

    if email_notifications_enabled?(recipient)
      deliver_email(
        message,
        email_template,
        metadata.merge(
          "recipient" => {
            "first_name" => recipient.first_name,
            "email" => recipient.email,
          },
          "recipient_name" => recipient.full_name
        )
      )
    end

    message
  end

  def self.deliver_mention(text:, sender:, context_url: nil, reference: nil)
    mentions = MentionDetectionService.extract_mentions(text)
    template = EmailTemplate.active.find_by(event_trigger: "user_mentioned")

    mentions.each do |mention_data|
      recipient = mention_data[:user]
      next if recipient == sender

      sender_name = sender.full_name
      deliver(
        recipient: recipient,
        sender: sender,
        subject: "#{sender_name} mentioned you",
        body_html: build_mention_html(text, sender, context_url),
        body_text: "#{sender_name} mentioned you: #{text}",
        message_type: "mention",
        email_template: template,
        reference: reference,
        metadata: {
          "context_url" => context_url,
          "mentioned_by" => sender.id,
          "text_snippet" => text.to_s.first(200),
        }
      )
    end
  end

  class << self
    private

    def email_notifications_enabled?(recipient)
      recipient.preference&.receive_mention_emails != false
    end

    def deliver_email(message, template, payload)
      return unless template

      delivery = EmailDelivery.create!(
        email_template: template,
        recipient_email: message.recipient.email,
        payload: payload.deep_stringify_keys,
        status: "pending"
      )
      EmailDispatcherWorker.perform_async(delivery.id)
    end

    def build_mention_html(text, sender, context_url)
      sender_name = ERB::Util.html_escape(sender.full_name)
      safe_text = ERB::Util.html_escape(text)
      link = context_url.present? ? %(<p><a href="#{ERB::Util.html_escape(context_url)}">View in context</a></p>) : ""
      "<p><strong>#{sender_name}</strong> mentioned you:</p><blockquote>#{safe_text}</blockquote>#{link}"
    end
  end
end
