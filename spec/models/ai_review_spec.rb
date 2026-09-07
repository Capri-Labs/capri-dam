require "rails_helper"

RSpec.describe CommentThread, "AI suggestion triage" do
  let(:user) { create(:user) }
  let(:asset) { create(:asset, user: user) }
  let(:review) { AiReview.create!(asset: asset, requested_by: user, ai_model_name: "gpt-4o") }

  def suggestion(state: "pending")
    asset.comment_threads.create!(ai_review: review, suggestion_state: state)
  end

  def human_thread
    asset.comment_threads.create!(created_by: user)
  end

  describe "authorship" do
    # The check constraint predates machine authorship; a thread attributable
    # to a recorded run is still attributable.
    it "accepts a thread authored by an AI review with no user or guest" do
      thread = asset.comment_threads.create!(ai_review: review, suggestion_state: "pending")

      expect(thread).to be_persisted
      expect(thread.created_by).to be_nil
    end

    it "still rejects a thread with no author at all" do
      thread = asset.comment_threads.build

      expect(thread).not_to be_valid
      expect(thread.errors[:base].join).to match(/must be opened by/)
    end

    it "names the model rather than a person" do
      expect(suggestion.creator_display_name).to eq("Review assistant (gpt-4o)")
    end
  end

  describe "validation" do
    # Otherwise a person's remark could be "dismissed" through the suggestion
    # path, bypassing the resolve/reopen lifecycle entirely.
    it "refuses a triage state on a human thread" do
      thread = asset.comment_threads.build(created_by: user, suggestion_state: "pending")

      expect(thread).not_to be_valid
      expect(thread.errors[:suggestion_state].join).to match(/only applies/)
    end

    it "refuses an unknown triage state" do
      thread = asset.comment_threads.build(ai_review: review, suggestion_state: "maybe")

      expect(thread).not_to be_valid
    end
  end

  describe ".triaged" do
    it "excludes pending suggestions" do
      suggestion
      expect(asset.comment_threads.triaged).to be_empty
    end

    # Regression: `where.not(suggestion_state: "pending")` is NULL-unsafe and
    # would hide every human-authored thread in the system.
    it "includes human threads, whose triage state is NULL" do
      thread = human_thread
      expect(asset.comment_threads.triaged).to include(thread)
    end

    it "includes accepted and dismissed suggestions" do
      accepted = suggestion(state: "accepted")
      dismissed = suggestion(state: "dismissed")

      expect(asset.comment_threads.triaged).to include(accepted, dismissed)
    end
  end

  describe "#accept_suggestion!" do
    it "admits the suggestion into the review and records who decided" do
      thread = suggestion
      thread.accept_suggestion!(user: user)

      expect(thread.suggestion_state).to eq("accepted")
      expect(thread.suggestion_decided_by).to eq(user)
      expect(thread.suggestion_decided_at).to be_present
      expect(asset.comment_threads.triaged).to include(thread)
    end

    # Laundering machine output into a person's name would destroy the audit
    # trail that agent_type exists to keep.
    it "does not rewrite the comment's authorship to the accepting human" do
      thread = suggestion
      comment = thread.comments.create!(body: "Logo clipped", agent_type: "software", agent_name: "gpt-4o")

      thread.accept_suggestion!(user: user)

      expect(comment.reload.agent_type).to eq("software")
      expect(comment.author).to be_nil
    end

    it "refuses to act on a thread that is not a pending suggestion" do
      expect { human_thread.accept_suggestion!(user: user) }.to raise_error(ArgumentError)
    end
  end

  describe "#dismiss_suggestion!" do
    it "records the rejection" do
      thread = suggestion
      thread.dismiss_suggestion!(user: user)

      expect(thread.suggestion_state).to eq("dismissed")
      expect(thread.suggestion_decided_by).to eq(user)
    end

    # A silently deleted false positive is simply raised again next run, and
    # is the only evidence available for tuning the model.
    it "keeps the thread rather than deleting it" do
      thread = suggestion
      thread.dismiss_suggestion!(user: user)

      expect(described_class.find_by(id: thread.id)).to be_present
    end
  end
end

RSpec.describe AiReview do
  let(:user) { create(:user) }
  let(:asset) { create(:asset, user: user) }

  it "defaults to a queued run under a known profile" do
    review = described_class.create!(asset: asset, requested_by: user)

    expect(review.status).to eq("queued")
    expect(review.profile).to eq("brand_guidelines")
    expect(review.profile_label).to be_present
  end

  # The profile is an allow-list rather than a free-text prompt, so the
  # endpoint cannot be used to run arbitrary instructions against assets.
  it "refuses an unknown profile" do
    review = described_class.new(asset: asset, profile: "ignore-all-previous-instructions")

    expect(review).not_to be_valid
  end

  it "records failure with a reason rather than hanging in running" do
    review = described_class.create!(asset: asset)
    review.fail!("gateway timeout")

    expect(review.status).to eq("failed")
    expect(review.error_message).to eq("gateway timeout")
    expect(review).to be_terminal
  end

  it "tells the gateway where to send findings without leaking storage credentials" do
    review = described_class.create!(asset: asset)
    payload = review.to_gateway_payload

    expect(payload[:event]).to eq("ai_review.dispatch")
    expect(payload[:callback_url]).to include("/api/v1/ai_reviews/#{review.id}/findings")
    expect(payload.to_json).not_to match(/secret|access_key|signature/i)
  end

  # A run whose findings a team is acting on is part of the human record.
  it "is not destroyable once a finding has been accepted" do
    review = described_class.create!(asset: asset)
    asset.comment_threads.create!(ai_review: review, suggestion_state: "accepted")

    expect(review).not_to be_destroyable
  end

  it "is destroyable while its findings are all untriaged" do
    review = described_class.create!(asset: asset)
    asset.comment_threads.create!(ai_review: review, suggestion_state: "pending")

    expect(review).to be_destroyable
  end
end
