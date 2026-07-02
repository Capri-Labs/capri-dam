require 'rails_helper'

RSpec.describe 'Api::V1::Webhooks coverage', type: :request do
  let(:connector) { create(:system_connector) }
  let(:payload) { { event: 'asset.created', id: 'asset-1' }.to_json }

  def signature_for(body, secret = connector.webhook_secret)
    OpenSSL::HMAC.base64digest(OpenSSL::Digest.new('sha256'), secret, body)
  end

  it 'accepts a valid x-hub-signature-256 webhook and enqueues ingestion' do
    allow(IngestionWorker).to receive(:perform_async)

    post "/api/v1/webhooks/connectors/#{connector.id}/receive",
         params: payload,
         headers: { 'CONTENT_TYPE' => 'application/json', 'x-hub-signature-256' => signature_for(payload) }

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to eq('status' => 'accepted')
    expect(IngestionWorker).to have_received(:perform_async).with(connector.id, a_string_including('asset.created', 'asset-1'))
  end

  it 'accepts Adobe signature headers' do
    allow(IngestionWorker).to receive(:perform_async)

    post "/api/v1/webhooks/connectors/#{connector.id}/receive",
         params: payload,
         headers: { 'CONTENT_TYPE' => 'application/json', 'x-adobe-signature' => signature_for(payload) }

    expect(response).to have_http_status(:ok)
  end

  it 'rejects missing or invalid signatures and logs invalid attempts' do
    allow(Rails.logger).to receive(:warn)

    post "/api/v1/webhooks/connectors/#{connector.id}/receive", params: payload, headers: { 'CONTENT_TYPE' => 'application/json' }
    expect(response).to have_http_status(:unauthorized)

    post "/api/v1/webhooks/connectors/#{connector.id}/receive",
         params: payload,
         headers: { 'CONTENT_TYPE' => 'application/json', 'x-hub-signature-256' => signature_for('other') }
    expect(response).to have_http_status(:unauthorized)
    expect(Rails.logger).to have_received(:warn).with(/Invalid webhook signature attempt/)
  end

  it 'returns 401 for unknown connectors before the action runs' do
    post '/api/v1/webhooks/connectors/999999/receive', params: payload, headers: { 'CONTENT_TYPE' => 'application/json', 'x-hub-signature-256' => signature_for(payload, 'secret') }

    expect(response).to have_http_status(:unauthorized)
  end
end
