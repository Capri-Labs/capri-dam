# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::AiReviews", type: :request do
  let(:owner) { create(:user) }
  let(:other) { create(:user) }
  # Root-level: folder policies do not apply, isolating this from the folder
  # permission engine, which has its own specs.
  let(:asset) { create(:asset, user: owner, title: "Hero shot") }

  let(:gateway_secret) { "test-gateway-secret" }

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("GATEWAY_SECRET", nil).and_return(gateway_secret)
  end

  def gateway_headers(secret = gateway_secret)
    { "X-Gateway-Secret" => secret }
  end

  def finding
    {
      title: "Logo outside safe area",
      detail: "The wordmark sits too close to the trim edge.",
      confidence: 0.9,
      annotations: [ { shape: "rect", bbox: { x: 0.1, y: 0.1, w: 0.2, h: 0.2 } } ],
    }
  end

  describe "POST /api/v1/assets/:asset_id/ai_reviews" do
    before { sign_in owner }

    it "queues a run and dispatches it" do
      expect(AiReviewWorker).to receive(:perform_async)

      post "/api/v1/assets/#{asset.id}/ai_reviews", params: { profile: "accessibility" }, as: :json

      expect(response).to have_http_status(:created), response.body
      expect(response.parsed_body.dig("review", "status")).to eq("queued")
      expect(response.parsed_body.dig("review", "profile")).to eq("accessibility")
    end

    # A second run in flight would duplicate every finding into the queue.
    it "refuses to start a second run while one is in flight" do
      AiReview.create!(asset: asset, status: "running")

      post "/api/v1/assets/#{asset.id}/ai_reviews", as: :json

      expect(response).to have_http_status(:conflict)
    end

    it "refuses an unknown profile" do
      post "/api/v1/assets/#{asset.id}/ai_reviews", params: { profile: "arbitrary-prompt" }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "404s for an asset that does not exist" do
      post "/api/v1/assets/#{SecureRandom.uuid}/ai_reviews", as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/ai_reviews/:id/findings" do
    let(:review) { AiReview.create!(asset: asset, status: "running", ai_model_name: "gpt-4o") }

    it "imports findings as pending suggestions" do
      post "/api/v1/ai_reviews/#{review.id}/findings",
           params: { findings: [ finding ] }.to_json,
           headers: gateway_headers.merge("CONTENT_TYPE" => "application/json")

      expect(response).to have_http_status(:ok), response.body
      expect(response.parsed_body["imported"]).to eq(1)
      expect(asset.comment_threads.pending_suggestions.count).to eq(1)
    end

    # The callback is the one unauthenticated-by-session entry point, so its
    # secret is the whole boundary.
    it "rejects a caller without the gateway secret" do
      post "/api/v1/ai_reviews/#{review.id}/findings",
           params: { findings: [ finding ] }.to_json,
           headers: { "CONTENT_TYPE" => "application/json" }

      expect(response).to have_http_status(:unauthorized)
      expect(asset.comment_threads).to be_empty
    end

    it "rejects a caller with the wrong secret" do
      post "/api/v1/ai_reviews/#{review.id}/findings",
           params: { findings: [ finding ] }.to_json,
           headers: gateway_headers("wrong").merge("CONTENT_TYPE" => "application/json")

      expect(response).to have_http_status(:unauthorized)
    end

    it "does not accept findings from a signed-in user without the secret" do
      sign_in owner

      post "/api/v1/ai_reviews/#{review.id}/findings",
           params: { findings: [ finding ] }.to_json,
           headers: { "CONTENT_TYPE" => "application/json" }

      expect(response).to have_http_status(:unauthorized)
    end

    it "records a gateway-side failure" do
      post "/api/v1/ai_reviews/#{review.id}/findings",
           params: { error: "vision model timed out" }.to_json,
           headers: gateway_headers.merge("CONTENT_TYPE" => "application/json")

      expect(review.reload.status).to eq("failed")
      expect(review.error_message).to eq("vision model timed out")
    end

    # A retried or replayed delivery must not duplicate findings a reviewer
    # has already triaged.
    it "ignores a delivery for a run that already finished" do
      review.complete!(1)

      post "/api/v1/ai_reviews/#{review.id}/findings",
           params: { findings: [ finding ] }.to_json,
           headers: gateway_headers.merge("CONTENT_TYPE" => "application/json")

      expect(response.parsed_body["status"]).to eq("ignored")
      expect(asset.comment_threads).to be_empty
    end
  end

  describe "suggestions and the review listing" do
    let(:review) { AiReview.create!(asset: asset, ai_model_name: "gpt-4o") }
    let!(:suggested) do
      thread = asset.comment_threads.create!(ai_review: review, suggestion_state: "pending")
      thread.comments.create!(body: "Logo clipped", agent_type: "software", agent_name: "gpt-4o")
      thread
    end

    before { sign_in owner }

    # The central guarantee: machine output is not feedback until a human says so.
    it "keeps pending suggestions out of the normal thread list" do
      get "/api/v1/assets/#{asset.id}/comments", as: :json

      expect(response.parsed_body["threads"]).to be_empty
      expect(response.parsed_body.dig("meta", "pending_suggestions")).to eq(1)
    end

    it "keeps pending suggestions out of an export a client might receive" do
      get "/api/v1/assets/#{asset.id}/comments/export", as: :json

      expect(response.body).not_to include("Logo clipped")
    end

    it "lists them in the triage queue" do
      get "/api/v1/assets/#{asset.id}/ai_reviews/pending", as: :json

      expect(response.parsed_body["threads"].length).to eq(1)
      expect(response.parsed_body["threads"].first.dig("suggestion", "state")).to eq("pending")
    end

    it "admits an accepted suggestion into the review" do
      post "/api/v1/comment_threads/#{suggested.id}/accept_suggestion", as: :json

      expect(response).to have_http_status(:ok), response.body
      expect(suggested.reload.suggestion_state).to eq("accepted")

      get "/api/v1/assets/#{asset.id}/comments", as: :json
      expect(response.parsed_body["threads"].length).to eq(1)
    end

    it "keeps a dismissed suggestion out of the review but does not delete it" do
      post "/api/v1/comment_threads/#{suggested.id}/dismiss_suggestion", as: :json

      expect(suggested.reload.suggestion_state).to eq("dismissed")
      expect(CommentThread.find_by(id: suggested.id)).to be_present
    end

    it "refuses to triage the same suggestion twice" do
      post "/api/v1/comment_threads/#{suggested.id}/accept_suggestion", as: :json
      post "/api/v1/comment_threads/#{suggested.id}/accept_suggestion", as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "refuses to triage a human thread" do
      human = asset.comment_threads.create!(created_by: owner)

      post "/api/v1/comment_threads/#{human.id}/accept_suggestion", as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "reports which model produced a suggestion" do
      get "/api/v1/assets/#{asset.id}/ai_reviews/pending", as: :json

      suggestion = response.parsed_body["threads"].first["suggestion"]
      expect(suggestion["model_name"]).to eq("gpt-4o")
    end

    it "marks the comment as machine-authored" do
      get "/api/v1/assets/#{asset.id}/ai_reviews/pending", as: :json

      comment = response.parsed_body["threads"].first["comments"].first
      expect(comment["agent_type"]).to eq("software")
      expect(comment["author"]).to be_nil
    end
  end

  describe "guest exposure" do
    let(:review) { AiReview.create!(asset: asset, ai_model_name: "gpt-4o") }

    # An unreviewed machine guess reaching a client is the worst outcome here.
    it "never shows a pending suggestion to an external reviewer" do
      # Cleared for external release on purpose. Left as internal_only the asset
      # is filtered out of the link's scope and this endpoint 404s, which would
      # make the assertion below pass without ever exercising the AI-suggestion
      # suppression it exists to prove.
      asset.update!(usage_terms: "royalty_free")
      thread = asset.comment_threads.create!(ai_review: review, suggestion_state: "pending")
      thread.comments.create!(body: "Logo clipped", agent_type: "software", agent_name: "gpt-4o")

      _link, token = ReviewLink.mint(target: asset, created_by: owner, name: "Client review")

      get "/s/reviews/#{token}/assets/#{asset.id}/threads",
          headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok), response.body
      expect(response.body).not_to include("Logo clipped")
      expect(response.parsed_body["threads"]).to be_empty
    end
  end
end
