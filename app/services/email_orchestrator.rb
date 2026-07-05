class EmailOrchestrator
  # Usage: EmailOrchestrator.trigger('user_created', 'john@aldi.com', { 'user' => { 'first_name' => 'John' } })

  def self.trigger(event_trigger, recipient_email, payload = {})
    template = EmailTemplate.active.find_by(event_trigger: event_trigger)

    unless template
      Rails.logger.warn("[Email Engine] Aborted: No active template found for '#{event_trigger}'")
      return false
    end

    # Liquid requires strictly stringified keys, so we deeply format the hash.
    # Global branding/date/support tokens (see GlobalTemplateVariables) are
    # backfilled here so every template has access to them without every
    # caller needing to pass them explicitly; explicit payload values win.
    liquid_payload = GlobalTemplateVariables.with_defaults(payload)

    # 1. Create the Audit Log / Outbox record immediately
    delivery = EmailDelivery.create!(
      email_template: template,
      recipient_email: recipient_email,
      payload: liquid_payload,
      status: "pending"
    )

    # 2. Throw it over the wall to Redis/Sidekiq for asynchronous processing
    EmailDispatcherWorker.perform_async(delivery.id)

    true
  end
end
