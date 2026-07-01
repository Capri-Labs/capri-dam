class MentionProcessorWorker
  include Sidekiq::Worker

  sidekiq_options queue: "default", retry: 3

  def perform(text, sender_id, context_url = nil, reference_type = nil, reference_id = nil)
    sender = User.find_by(id: sender_id)
    return unless sender

    reference = reference_type&.safe_constantize&.find_by(id: reference_id) if reference_type.present? && reference_id.present?

    InboxDeliveryService.deliver_mention(
      text: text,
      sender: sender,
      context_url: context_url,
      reference: reference
    )
  end
end
