# frozen_string_literal: true

# WorkflowSmsWorker – delivers an SMS notification for a workflow step.
#
# Enqueued by WorkflowActionExecutor#send_sms so that provider latency
# never blocks the workflow engine.
#
# Currently supports Twilio via environment variables:
#   TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_FROM_NUMBER
#
# Falls back to a structured log entry when credentials are absent (useful
# for development / test environments).
class WorkflowSmsWorker
  include Sidekiq::Worker
  sidekiq_options queue: "notifications", retry: 3

  def perform(instance_id, phone, message)
    return if phone.blank? || message.blank?

    instance = WorkflowInstance.find_by(id: instance_id)
    asset    = instance&.asset

    # Expand any remaining tokens that weren't resolved before enqueueing
    body = message
           .gsub("{{asset.title}}",   asset&.title.to_s)
           .gsub("{{asset.id}}",      asset&.id.to_s)
           .gsub("{{asset.status}}", asset&.status.to_s)

    if twilio_configured?
      send_via_twilio(phone, body)
    else
      Rails.logger.info("[WorkflowSmsWorker] SMS to #{phone}: #{body.truncate(80)}")
    end
  rescue StandardError => e
    Rails.logger.error("[WorkflowSmsWorker] Failed for instance #{instance_id} → #{phone}: #{e.message}")
    raise
  end

  private

  def twilio_configured?
    ENV["TWILIO_ACCOUNT_SID"].present? &&
      ENV["TWILIO_AUTH_TOKEN"].present? &&
      ENV["TWILIO_FROM_NUMBER"].present?
  end

  def send_via_twilio(to, body)
    conn = Faraday.new("https://api.twilio.com") do |f|
      f.request :url_encoded
      f.options.timeout = 10
    end

    conn.post(
      "/2010-04-01/Accounts/#{ENV["TWILIO_ACCOUNT_SID"]}/Messages.json",
      { To: to, From: ENV["TWILIO_FROM_NUMBER"], Body: body },
    ) do |req|
      req.headers["Authorization"] =
        "Basic #{Base64.strict_encode64("#{ENV["TWILIO_ACCOUNT_SID"]}:#{ENV["TWILIO_AUTH_TOKEN"]}")}"
    end

    Rails.logger.info("[WorkflowSmsWorker] SMS dispatched to #{to}")
  end
end
