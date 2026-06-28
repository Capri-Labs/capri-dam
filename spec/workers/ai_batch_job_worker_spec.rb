# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiBatchJobWorker, type: :worker do
  let(:redis) { instance_double("Redis") }

  before do
    allow(Sidekiq).to receive(:redis).and_yield(redis)
    allow(redis).to receive(:publish)
  end

  describe "#perform" do
    it "no-ops when the job is missing" do
      expect { described_class.new.perform(0) }.not_to raise_error
    end

    it "no-ops when the job is not queued" do
      job = create(:ai_batch_job, :running)
      described_class.new.perform(job.id)
      expect(job.reload.status).to eq("running")
      expect(redis).not_to have_received(:publish)
    end

    context "with queued targets" do
      let!(:assets) { create_list(:asset, 3) }
      let(:job)     { create(:ai_batch_job, task_type: "metadata_extraction", target_scope: "all_assets") }

      it "marks the job running and records the total" do
        described_class.new.perform(job.id)
        job.reload
        expect(job.status).to eq("running")
        expect(job.total_count).to eq(3)
        expect(job.started_at).to be_present
      end

      it "broadcasts a dispatch event to the gateway" do
        described_class.new.perform(job.id)
        expect(redis).to have_received(:publish).with("ai_gateway_events", kind_of(String))
      end
    end

    it "completes immediately when no targets match" do
      job = create(:ai_batch_job, target_scope: "all_assets")
      described_class.new.perform(job.id)
      job.reload
      expect(job.status).to eq("completed")
      expect(job.total_count).to eq(0)
      expect(redis).not_to have_received(:publish)
    end

    it "marks the job failed and re-raises on error" do
      job = create(:ai_batch_job, target_scope: "all_assets")
      create(:asset)
      allow(Ai::BatchTaskRegistry).to receive(:resolve_targets).and_raise(StandardError.new("boom"))

      expect { described_class.new.perform(job.id) }.to raise_error(StandardError, "boom")
      expect(job.reload.status).to eq("failed")
      expect(job.error_message).to eq("boom")
    end
  end
end
