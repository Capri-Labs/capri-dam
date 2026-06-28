# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiBatchJob, type: :model do
  describe "validations" do
    subject { build(:ai_batch_job) }

    it { is_expected.to be_valid }

    it "rejects an unknown task_type" do
      subject.task_type = "not_a_task"
      expect(subject).not_to be_valid
      expect(subject.errors[:task_type]).to be_present
    end

    it "accepts every registered task_type" do
      Ai::BatchTaskRegistry.task_keys.each do |key|
        subject.task_type = key
        expect(subject).to be_valid, "expected #{key} to be valid"
      end
    end

    it "rejects an unknown target_scope" do
      subject.target_scope = "nowhere"
      expect(subject).not_to be_valid
    end

    it "rejects an unknown status" do
      subject.status = "imploded"
      expect(subject).not_to be_valid
    end

    it "rejects out-of-range concurrency" do
      subject.concurrency = 0
      expect(subject).not_to be_valid
      subject.concurrency = AiBatchJob::MAX_CONCURRENCY + 1
      expect(subject).not_to be_valid
    end

    it "rejects negative counters" do
      subject.processed_count = -1
      expect(subject).not_to be_valid
    end
  end

  describe "#progress_percent" do
    it "returns 0 when nothing is queued" do
      expect(build(:ai_batch_job, total_count: 0).progress_percent).to eq(0)
    end

    it "computes the rounded percentage" do
      job = build(:ai_batch_job, total_count: 200, processed_count: 50)
      expect(job.progress_percent).to eq(25)
    end

    it "clamps to 100" do
      job = build(:ai_batch_job, total_count: 10, processed_count: 50)
      expect(job.progress_percent).to eq(100)
    end
  end

  describe "#terminal?" do
    it "is true for completed/failed/cancelled" do
      AiBatchJob::TERMINAL_STATUSES.each do |s|
        expect(build(:ai_batch_job, status: s).terminal?).to be(true)
      end
    end

    it "is false for queued/running" do
      expect(build(:ai_batch_job, status: "running").terminal?).to be(false)
    end
  end

  describe "scopes" do
    it ".active excludes terminal jobs" do
      active = create(:ai_batch_job, :running)
      create(:ai_batch_job, :completed)
      expect(AiBatchJob.active).to contain_exactly(active)
    end
  end

  describe "#to_gateway_payload" do
    it "includes the task capability and target ids" do
      job = build(:ai_batch_job, task_type: "metadata_extraction")
      payload = job.to_gateway_payload(%w[a b])
      expect(payload[:event]).to eq("ai_batch.dispatch")
      expect(payload[:capability]).to eq("metadata.extract")
      expect(payload[:target_ids]).to eq(%w[a b])
    end
  end
end
