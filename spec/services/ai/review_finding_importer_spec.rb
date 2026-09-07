require "rails_helper"

RSpec.describe Ai::ReviewFindingImporter do
  let(:user) { create(:user) }
  let(:asset) { create(:asset, user: user, title: "Hero shot", properties: { "content_type" => "image/jpeg" }) }
  let(:review) { AiReview.create!(asset: asset, requested_by: user, ai_model_name: "gpt-4o") }

  def finding(**overrides)
    {
      title: "Logo outside safe area",
      detail: "The wordmark sits 2% from the trim edge.",
      confidence: 0.9,
      annotations: [ { shape: "rect", bbox: { x: 0.1, y: 0.1, w: 0.2, h: 0.2 } } ],
    }.merge(overrides)
  end

  describe "#import" do
    it "creates a real annotated thread the review owns" do
      result = described_class.new(review).import([ finding ])

      expect(result.imported).to eq(1)
      thread = asset.comment_threads.sole
      expect(thread.ai_review).to eq(review)
      expect(thread.suggestion_state).to eq("pending")
      expect(thread.status).to eq("open")
    end

    it "attributes the comment to the machine, not to a person" do
      described_class.new(review).import([ finding ])

      comment = asset.comment_threads.sole.comments.sole
      expect(comment.agent_type).to eq("software")
      expect(comment.agent_name).to eq("gpt-4o")
      expect(comment.author).to be_nil
      expect(comment.confidence.to_f).to eq(0.9)
      # W3C motivation for a quality judgement.
      expect(comment.motivation).to eq("assessing")
    end

    it "stores the geometry so the overlay can draw it" do
      described_class.new(review).import([ finding ])

      target = asset.comment_threads.sole.comments.sole.annotation_targets.sole
      expect(target.shape).to eq("rect")
      expect(target.bbox_x).to eq(0.1)
      expect(target.bbox_w).to eq(0.2)
    end

    it "marks the run completed with a finding count" do
      described_class.new(review).import([ finding, finding ])

      expect(review.reload.status).to eq("completed")
      expect(review.findings_count).to eq(2)
    end

    it "records that a clean asset was actually checked" do
      described_class.new(review).import([])

      # The distinction that justifies storing runs separately: "looked, found
      # nothing" must not look like "never looked".
      expect(review.reload.status).to eq("completed")
      expect(review.findings_count).to eq(0)
      expect(asset.comment_threads).to be_empty
    end

    # A pending suggestion is machine output, not feedback.
    it "hides suggestions from the review until accepted" do
      described_class.new(review).import([ finding ])

      expect(asset.comment_threads.triaged).to be_empty
      expect(asset.comment_threads.pending_suggestions.count).to eq(1)
    end

    it "keeps suggestions internal so they cannot reach a guest" do
      described_class.new(review).import([ finding ])

      expect(asset.comment_threads.sole.visibility).to eq("internal")
      expect(asset.comment_threads.visible_to_guests).to be_empty
    end

    describe "treating the gateway payload as untrusted" do
      it "drops a finding the model was not confident about" do
        result = described_class.new(review).import([ finding(confidence: 0.1) ])

        expect(result.imported).to eq(0)
        expect(result.skipped).to eq(1)
      end

      it "drops a finding with no readable body" do
        result = described_class.new(review).import([ { title: "", detail: "", confidence: 0.9 } ])

        expect(result.imported).to eq(0)
      end

      # The database CHECK rejects x+w > 1; an unclamped box would abort the
      # whole import and lose every other finding in the run.
      it "clamps a bounding box that runs off the edge" do
        described_class.new(review).import([
          finding(annotations: [ { shape: "rect", bbox: { x: 0.8, y: 0.9, w: 0.9, h: 0.9 } } ]),
        ])

        target = asset.comment_threads.sole.comments.sole.annotation_targets.sole
        expect(target.bbox_x + target.bbox_w).to be <= 1.0
        expect(target.bbox_y + target.bbox_h).to be <= 1.0
      end

      it "clamps a negative coordinate" do
        described_class.new(review).import([
          finding(annotations: [ { shape: "rect", bbox: { x: -5, y: -5, w: 0.2, h: 0.2 } } ]),
        ])

        target = asset.comment_threads.sole.comments.sole.annotation_targets.sole
        expect(target.bbox_x).to eq(0.0)
        expect(target.bbox_y).to eq(0.0)
      end

      it "keeps the finding but drops a path-only shape with no path" do
        described_class.new(review).import([ finding(annotations: [ { shape: "freehand" } ]) ])

        comment = asset.comment_threads.sole.comments.sole
        expect(comment.annotation_targets).to be_empty
        expect(comment.body).to be_present
      end

      it "falls back to a known shape when the model invents one" do
        described_class.new(review).import([
          finding(annotations: [ { shape: "hexagon", bbox: { x: 0.1, y: 0.1, w: 0.1, h: 0.1 } } ]),
        ])

        expect(asset.comment_threads.sole.comments.sole.annotation_targets.sole.shape).to eq("rect")
      end

      it "caps a runaway run rather than flooding the triage queue" do
        result = described_class.new(review).import(Array.new(80) { finding })

        expect(result.imported).to eq(described_class::MAX_FINDINGS)
      end

      it "truncates an over-long body instead of failing validation" do
        result = described_class.new(review).import([ finding(detail: "x" * 20_000) ])

        expect(result.imported).to eq(1)
        expect(asset.comment_threads.sole.comments.sole.body.length)
          .to be <= Comment::MAX_BODY_LENGTH
      end

      it "skips one bad finding without losing the good ones" do
        result = described_class.new(review).import([ finding, { detail: "" }, finding ])

        expect(result.imported).to eq(2)
        expect(result.skipped).to eq(1)
      end
    end

    it "quotes the guideline that was breached so the note is actionable" do
      described_class.new(review).import([ finding(rule: "Brand Book 4.2") ])

      expect(asset.comment_threads.sole.comments.sole.body).to include("Brand Book 4.2")
    end

    it "infers video media type from the asset" do
      video = create(:asset, user: user, properties: { "content_type" => "video/mp4" })
      video_review = AiReview.create!(asset: video, requested_by: user)

      described_class.new(video_review).import([ finding ])

      expect(video.comment_threads.sole.comments.sole.annotation_targets.sole.media_type)
        .to eq("video")
    end
  end
end
