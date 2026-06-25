class Api::V1::WebhooksController < ApplicationController
  # Bypass standard CSRF and user authentication for machine-to-machine webhooks
  skip_before_action :verify_authenticity_token
  before_action :verify_webhook_signature!

  def receive
    connector = SystemConnector.find(params[:connector_id])
    payload = request.request_parameters

    # In a production environment, you immediately hand this off to Redis/Sidekiq
    # to free up the web thread, rather than processing the JSON synchronously.
    IngestionWorker.perform_async(connector.id, payload.to_json)

    # Always return a fast 200 OK to the source system so it doesn't retry
    render json: { status: "accepted" }, status: :ok
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Ingestion bridge not found" }, status: :not_found
  end

  private

  def verify_webhook_signature!
    connector = SystemConnector.find_by(id: params[:connector_id])
    return head :unauthorized unless connector

    # Different systems use different signature headers.
    # Adobe I/O uses x-adobe-signature, generic systems often use x-hub-signature-256
    signature_header = request.headers["x-adobe-signature"] || request.headers["x-hub-signature-256"]
    return head :unauthorized unless signature_header

    # Recreate the HMAC hash using your local secret and the raw request body
    request.body.rewind
    payload_body = request.body.read

    expected_signature = OpenSSL::HMAC.base64digest(
      OpenSSL::Digest.new("sha256"),
      connector.webhook_secret,
      payload_body
    )

    # SecureCompare mitigates timing attacks
    unless ActiveSupport::SecurityUtils.secure_compare(signature_header, expected_signature)
      Rails.logger.warn(" Security Alert: Invalid webhook signature attempt on connector #{connector.id}")
      head :unauthorized
    end
  end
end
