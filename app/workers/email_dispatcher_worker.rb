class EmailDispatcherWorker
  include Sidekiq::Worker

  # Configure Sidekiq strictly for 3 retries on the mailers queue.
  sidekiq_options queue: "mailers", retry: 3

  # Errors the SMTP server itself flags as non-recoverable (bad credentials,
  # malformed commands). These are never retried -- exponential backoff would
  # only delay an inevitable, identical failure 3 more times.
  PERMANENT_ERRORS = [
    Net::SMTPAuthenticationError,
    Net::SMTPSyntaxError,
  ].freeze

  # Explicit exponential backoff for transient errors (e.g. `421 Service
  # unavailable`, connection timeouts): 10s, 40s, 90s for attempts 1..3.
  sidekiq_retry_in do |count, _exception|
    10 * ((count + 1)**2)
  end

  # If the email fails 3 times, Sidekiq natively catches it here.
  # We use this block to permanently mark the delivery as failed in your database.
  sidekiq_retries_exhausted do |msg, ex|
    delivery = EmailDelivery.find_by(id: msg["args"][0])
    delivery&.mark_as_failed!("Exhausted 3 retries. Final SMTP Error: #{ex.message}")
  end

  def perform(delivery_id)
    delivery = EmailDelivery.find_by(id: delivery_id)

    # Safety guard: Prevent double-sending if the job was accidentally duplicated
    return if delivery.nil? || delivery.status == "sent"

    template = delivery.email_template
    payload = delivery.payload

    # 1. Parse and Render the Liquid Templates with the saved JSONB payload
    subject = Liquid::Template.parse(template.subject).render(payload)
    html_body = Liquid::Template.parse(template.html_body.to_s).render(payload)
    text_body = Liquid::Template.parse(template.text_body.to_s).render(payload)

    begin
      # 2. Attempt SMTP delivery through the single centralized dispatcher,
      #    which guarantees the validated database SMTP configuration is
      #    applied before every transmission.
      CentralNotificationMailer.build_template_mail(
        to: delivery.recipient_email,
        subject: subject,
        html_body: html_body,
        text_body: text_body
      ).deliver_now

      # 3. On success, update the audit log
      delivery.mark_as_sent!

    rescue *PERMANENT_ERRORS => e
      # Non-recoverable SMTP errors are logged and marked failed immediately;
      # re-raising would just burn all 3 retries on an identical failure.
      delivery.update!(error_log: "Permanent SMTP failure: #{e.message}")
      delivery.mark_as_failed!("Permanent SMTP failure: #{e.message}")
      Rails.logger.error("[EmailDispatcherWorker] Permanent failure for delivery=#{delivery.id}: #{e.class} #{e.message}")

    rescue => e
      # Increment the internal database tracker for the UI, then re-raise the error.
      # Re-raising tells Sidekiq that the job failed, forcing it into the retry queue
      # with the exponential backoff configured above.
      delivery.increment!(:retry_count)
      delivery.update!(error_log: "Attempt #{delivery.retry_count} failed: #{e.message}")
      Rails.logger.warn("[EmailDispatcherWorker] Transient failure for delivery=#{delivery.id} attempt=#{delivery.retry_count}: #{e.class} #{e.message}")

      raise e
    end
  end
end
