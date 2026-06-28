# frozen_string_literal: true

require "rails_helper"

RSpec.describe StylePresetSyncWorker, type: :worker do
  subject(:worker) { described_class.new }

  let(:redis_double) { instance_double("Redis", publish: nil) }

  before do
    allow(Sidekiq).to receive(:redis).and_yield(redis_double)
  end

  describe "#perform" do
    context "when preset exists" do
      let!(:preset) { create(:style_preset) }

      it "publishes a style.preset.sync event to Redis" do
        worker.perform(preset.id)
        expect(redis_double).to have_received(:publish).with(
          "ai_gateway_events",
          include('"event":"style.preset.sync"')
        )
      end

      it "updates synced_at on success" do
        before = Time.current
        worker.perform(preset.id)
        expect(preset.reload.synced_at).to be >= before
        expect(preset.reload.synced_at).to be <= Time.current + 5.seconds
      end

      it "embeds preset slug and style_params in the payload" do
        # Capture the last publish call that contains the sync event
        sync_payload = nil
        allow(redis_double).to receive(:publish) do |_ch, pl|
          sync_payload = pl if pl.include?('"event":"style.preset.sync"')
        end

        worker.perform(preset.id)

        expect(sync_payload).not_to be_nil
        parsed = JSON.parse(sync_payload)
        expect(parsed["preset"]["slug"]).to eq(preset.slug)
        expect(parsed["preset"]["style_params"]).to eq(preset.style_params)
      end
    end

    context "when preset does not exist" do
      it "does not raise and does not publish a sync event" do
        expect { worker.perform(999_999) }.not_to raise_error
        expect(redis_double).not_to have_received(:publish).with(
          "ai_gateway_events", include('"event":"style.preset.sync"')
        )
      end
    end

    context "when Redis publish fails" do
      let!(:preset) { create(:style_preset) }

      it "re-raises for Sidekiq retry" do
        allow(redis_double).to receive(:publish).and_raise(StandardError, "Redis unavailable")
        expect { worker.perform(preset.id) }.to raise_error(StandardError, "Redis unavailable")
      end
    end
  end

  describe "Sidekiq options" do
    it "uses the smartai queue" do
      expect(described_class.sidekiq_options["queue"]).to eq("smartai")
    end
  end
end
