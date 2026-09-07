# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::CommentWebhookSubscriptions coverage', type: :request do
  let(:admin) { create(:user, :admin) }
  let(:folder) { create(:folder, user: admin) }
  let(:asset) { create(:asset, user: admin, folder: folder) }

  before { sign_in admin }

  def parsed_body
    response.parsed_body
  end

  def create_subscription(**attrs)
    CommentWebhookSubscription.create!(
      { name: 'Proofing vendor', url: 'https://vendor.example/hooks/capri' }.merge(attrs)
    )
  end

  describe 'GET /api/v1/comment_webhook_subscriptions' do
    it 'lists subscriptions and advertises the available events' do
      create_subscription

      get '/api/v1/comment_webhook_subscriptions'

      expect(response).to have_http_status(:ok)
      expect(parsed_body['events']).to match_array(CommentWebhookSubscription::EVENTS)
      expect(parsed_body['subscriptions'].size).to eq(1)
    end

    it 'never discloses the signing secret' do
      create_subscription

      get '/api/v1/comment_webhook_subscriptions'

      # Write-only after creation, so a hijacked admin session cannot harvest
      # signing keys for endpoints it did not create.
      expect(response.body).not_to include(CommentWebhookSubscription.first.secret)
      expect(parsed_body['subscriptions'].first).not_to have_key('secret')
    end

    it 'denies a non-admin' do
      sign_in create(:user)

      get '/api/v1/comment_webhook_subscriptions'

      expect(response).to have_http_status(:forbidden).or have_http_status(:unauthorized)
    end
  end

  describe 'POST /api/v1/comment_webhook_subscriptions' do
    it 'creates a subscription and returns the secret exactly once' do
      expect {
        post '/api/v1/comment_webhook_subscriptions', params: {
          comment_webhook_subscription: {
            name: 'Tracker', url: 'https://tracker.example/hook', events: [ 'thread.resolved' ]
          },
        }, as: :json
      }.to change(CommentWebhookSubscription, :count).by(1)

      expect(response).to have_http_status(:created)
      # The receiver needs it to verify signatures and it is unrecoverable later.
      expect(parsed_body['secret']).to be_present
      expect(parsed_body['events']).to eq([ 'thread.resolved' ])
    end

    it 'rejects a non-http URL' do
      post '/api/v1/comment_webhook_subscriptions', params: {
        comment_webhook_subscription: { name: 'Bad', url: 'ftp://vendor.example' },
      }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(parsed_body['errors'].join).to include('http(s)')
    end

    it 'rejects an unknown event name rather than silently never firing' do
      post '/api/v1/comment_webhook_subscriptions', params: {
        comment_webhook_subscription: { name: 'Typo', url: 'https://v.example', events: [ 'comment.creted' ] },
      }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(parsed_body['errors'].join).to include('comment.creted')
    end
  end

  describe 'PATCH /api/v1/comment_webhook_subscriptions/:id' do
    it 'clears the failure count so a repaired endpoint resumes' do
      subscription = create_subscription
      subscription.update_columns(consecutive_failures: 12)

      patch "/api/v1/comment_webhook_subscriptions/#{subscription.id}", params: {
        comment_webhook_subscription: { url: 'https://vendor.example/hooks/v2' },
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(subscription.reload.consecutive_failures).to eq(0)
      expect(subscription.url).to eq('https://vendor.example/hooks/v2')
    end

    it 'reports a suspended endpoint in its health block' do
      subscription = create_subscription
      subscription.update_columns(consecutive_failures: CommentWebhookSubscription::FAILURE_LIMIT)

      get "/api/v1/comment_webhook_subscriptions/#{subscription.id}"

      # Surfaced explicitly so an operator can see why an "active"
      # subscription has gone quiet.
      expect(parsed_body.dig('health', 'suspended')).to be(true)
      expect(parsed_body['active']).to be(true)
    end
  end

  describe 'DELETE /api/v1/comment_webhook_subscriptions/:id' do
    it 'removes the subscription' do
      subscription = create_subscription

      expect {
        delete "/api/v1/comment_webhook_subscriptions/#{subscription.id}"
      }.to change(CommentWebhookSubscription, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end
  end

  describe 'POST /api/v1/comment_webhook_subscriptions/:id/test' do
    it 'reports a reachable endpoint as ok' do
      subscription = create_subscription
      stub_request(:post, subscription.url).to_return(status: 200, body: 'ok')

      post "/api/v1/comment_webhook_subscriptions/#{subscription.id}/test"

      expect(response).to have_http_status(:ok)
      expect(parsed_body['ok']).to be(true)
      expect(parsed_body['status']).to eq(200)
    end

    it 'signs the ping so the integrator can verify their implementation' do
      subscription = create_subscription
      stub_request(:post, subscription.url).to_return(status: 200, body: 'ok')

      post "/api/v1/comment_webhook_subscriptions/#{subscription.id}/test"

      expect(WebMock).to have_requested(:post, subscription.url).with { |request|
        request.headers['X-Capri-Signature'] == subscription.signature_for(request.body)
      }
    end

    it 'reports an unreachable endpoint as a successful test with ok=false' do
      subscription = create_subscription
      stub_request(:post, subscription.url).to_timeout

      post "/api/v1/comment_webhook_subscriptions/#{subscription.id}/test"

      # A failed ping is a successful test: it told the integrator what is
      # wrong. A 5xx here would wrongly implicate Capri.
      expect(response).to have_http_status(:ok)
      expect(parsed_body['ok']).to be(false)
      expect(parsed_body['error']).to be_present
    end
  end
end
