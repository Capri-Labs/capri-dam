# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Api::V1::Webhooks', type: :request do

  # ===========================================================================
  # RECEIVE — POST /api/v1/webhooks/connectors/{connector_id}/receive
  # ===========================================================================
  path '/api/v1/webhooks/connectors/{connector_id}/receive' do
    parameter name: :connector_id, in: :path, type: :integer, required: true,
              description: 'ID of the SystemConnector this webhook is bound to'

    post 'Receive an inbound webhook event from an external system' do
      tags 'Webhooks'
      consumes 'application/json'
      produces 'application/json'
      description <<~DESC
        **Machine-to-machine endpoint.** CSRF verification is disabled; all
        requests must include a valid HMAC-SHA256 signature header instead.

        **Signature Verification**:
        1. The body is hashed using `HMAC-SHA256` with the connector's stored `webhook_secret`.
        2. The result must be provided in one of:
           - `x-adobe-signature` (Adobe I/O events)
           - `x-hub-signature-256` (GitHub-style webhooks)

        Payloads are **not processed synchronously** — they are immediately handed
        to `IngestionWorker` via Sidekiq to keep web thread latency near zero.
        Always return `200 OK` from your webhook source system after this responds.
      DESC

      parameter name: :'x-hub-signature-256', in: :header, type: :string, required: false,
                description: 'HMAC-SHA256 signature for generic webhook providers'
      parameter name: :'x-adobe-signature',   in: :header, type: :string, required: false,
                description: 'HMAC-SHA256 signature for Adobe I/O events'

      parameter name: :payload, in: :body, schema: {
        type: :object,
        description: 'Provider-specific event payload (arbitrary JSON — passed through to IngestionWorker)'
      }

      response '200', 'Event accepted and queued for async processing' do
        schema type: :object,
               properties: {
                 status: { type: :string, example: 'accepted' }
               }
        run_test!
      end

      response '401', 'Invalid or missing webhook signature' do
        run_test!
      end

      response '404', 'Connector not found' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end

end

