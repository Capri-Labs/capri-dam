# frozen_string_literal: true

require "rails_helper"

RSpec.describe C2paConfiguration, type: :model do
  describe ".current" do
    it "creates a record with safe defaults on first call" do
      expect(C2paConfiguration.count).to eq(0)
      cfg = C2paConfiguration.current
      expect(cfg).to be_persisted
      expect(cfg.gateway_c2pa_enabled).to be(false)
      expect(cfg.ai_disclosure_required).to be(true)
      expect(cfg.verification_strictness).to eq("lenient")
    end

    it "returns the same row on repeated calls (singleton)" do
      c1 = C2paConfiguration.current
      c2 = C2paConfiguration.current
      expect(c1.id).to eq(c2.id)
    end
  end

  describe "validations" do
    subject { build(:c2pa_configuration) }

    it { is_expected.to be_valid }

    it "rejects an unknown verification_strictness" do
      subject.verification_strictness = "whatever"
      expect(subject).not_to be_valid
    end

    it "accepts lenient and strict" do
      %w[lenient strict].each do |s|
        subject.verification_strictness = s
        expect(subject).to be_valid
      end
    end
  end

  describe "gateway broadcast" do
    let(:redis) { instance_double("Redis") }

    before do
      allow(Sidekiq).to receive(:redis).and_yield(redis)
      allow(redis).to receive(:publish)
    end

    it "publishes c2pa.config.updated after create" do
      create(:c2pa_configuration)
      expect(redis).to have_received(:publish).with("ai_gateway_events", include("c2pa.config.updated"))
    end

    it "publishes c2pa.config.updated after update" do
      cfg = create(:c2pa_configuration)
      cfg.update!(gateway_c2pa_enabled: true)
      expect(redis).to have_received(:publish).twice
    end

    it "swallows Redis errors without rolling back the save" do
      allow(redis).to receive(:publish).and_raise(Redis::BaseError)
      expect { create(:c2pa_configuration) }.not_to raise_error
      expect(C2paConfiguration.count).to eq(1)
    end
  end
end
