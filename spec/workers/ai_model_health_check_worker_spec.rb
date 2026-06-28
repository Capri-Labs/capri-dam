# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiModelHealthCheckWorker, type: :worker do
  subject(:worker) { described_class.new }

  let(:redis_double) { instance_double("Redis", publish: nil) }

  before do
    allow(Sidekiq).to receive(:redis).and_yield(redis_double)
  end

  describe "#perform" do
    context "when model exists and is enabled" do
      let!(:config) { create(:ai_model_config, enabled: true) }

      before { redis_double.as_null_object }

      it "publishes a model.health.check event to Redis" do
        worker.perform(config.id)
        expect(redis_double).to have_received(:publish).with(
          "ai_gateway_events",
          include('"event":"model.health.check"')
        )
      end

      it "includes model metadata in the payload" do
        captured = nil
        allow(redis_double).to receive(:publish) { |_ch, pl| captured = pl }

        worker.perform(config.id)

        # May be called multiple times (e.g. after_commit broadcast on create).
        # We want the health-check call, identified by its event key.
        expect(captured).not_to be_nil
        parsed = JSON.parse(captured)
        expect(parsed["model_id"]).to eq(config.id)
        expect(parsed["capability"]).to eq(config.capability)
      end
    end

    context "when model is disabled" do
      let!(:config) { create(:ai_model_config, :disabled) }

      it "does not publish a health-check event" do
        # Reset call count after the model creation broadcast
        redis_double.as_null_object
        allow(redis_double).to receive(:publish)

        worker.perform(config.id)

        # The only publish calls should be from model after_commit, not the worker
        expect(redis_double).not_to have_received(:publish).with(
          "ai_gateway_events", include('"event":"model.health.check"')
        )
      end
    end

    context "when model does not exist" do
      it "does not raise and does not publish a health-check event" do
        expect { worker.perform(999_999) }.not_to raise_error
        expect(redis_double).not_to have_received(:publish).with(
          "ai_gateway_events", include('"event":"model.health.check"')
        )
      end
    end
  end

  describe "Sidekiq options" do
    it "uses the smartai queue" do
      expect(described_class.sidekiq_options["queue"]).to eq("smartai")
    end
  end
end
