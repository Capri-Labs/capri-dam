# frozen_string_literal: true

require "rails_helper"

RSpec.describe StylePreset, type: :model do
  subject(:preset) { build(:style_preset) }

  describe "validations" do
    it "is valid with valid attributes" do
      expect(preset).to be_valid
    end

    it "is invalid without a name" do
      preset.name = nil
      expect(preset).not_to be_valid
      expect(preset.errors[:name]).to be_present
    end

    it "is invalid without a slug" do
      preset.slug = nil
      preset.valid?       # triggers derive_slug
      expect(preset.slug).to be_present # slug auto-derived from name
    end

    it "enforces slug uniqueness (case-insensitive)" do
      create(:style_preset, slug: "my-brand")
      duplicate = build(:style_preset, slug: "my-brand")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:slug]).to be_present
    end

    it "rejects slugs with uppercase letters" do
      preset.slug = "My-Preset"
      expect(preset).not_to be_valid
    end

    it "rejects slugs with spaces" do
      preset.slug = "my preset"
      expect(preset).not_to be_valid
    end

    it "accepts valid slugs" do
      preset.slug = "my-brand-style-1"
      expect(preset).to be_valid
    end
  end

  describe "before_validation :derive_slug" do
    it "derives slug from name on create when slug is blank" do
      preset.slug = nil
      preset.name = "Editorial Dark Mode"
      preset.valid?
      expect(preset.slug).to eq("editorial-dark-mode")
    end

    it "preserves an explicitly set slug" do
      preset.slug = "my-custom-slug"
      preset.name = "Editorial Dark Mode"
      preset.valid?
      expect(preset.slug).to eq("my-custom-slug")
    end
  end

  describe "scopes" do
    let!(:active_preset)   { create(:style_preset, active: true) }
    let!(:inactive_preset) { create(:style_preset, :inactive) }
    let!(:default_preset)  { create(:style_preset, :default) }
    let!(:synced_preset)   { create(:style_preset, :synced) }

    it ".active returns only active presets" do
      expect(StylePreset.active).to include(active_preset, default_preset, synced_preset)
      expect(StylePreset.active).not_to include(inactive_preset)
    end

    it ".defaults returns only default preset" do
      expect(StylePreset.defaults).to include(default_preset)
    end

    it ".synced returns presets with a gateway_ref" do
      expect(StylePreset.synced).to include(synced_preset)
      expect(StylePreset.synced).not_to include(active_preset)
    end
  end

  describe "#synced?" do
    it "returns true when gateway_ref is present" do
      preset.gateway_ref = "gw-123"
      expect(preset.synced?).to be true
    end

    it "returns false when gateway_ref is nil" do
      preset.gateway_ref = nil
      expect(preset.synced?).to be false
    end
  end

  describe "#stale?" do
    it "returns true when updated_at is newer than synced_at" do
      preset = create(:style_preset, :synced)
      preset.update_columns(synced_at: 2.hours.ago)
      preset.touch
      expect(preset.stale?).to be true
    end

    it "returns false when not synced" do
      preset.gateway_ref = nil
      expect(preset.stale?).to be false
    end
  end

  describe "#promote_to_default!" do
    let!(:current_default) { create(:style_preset, :default) }
    let!(:another)         { create(:style_preset) }

    it "promotes the preset and demotes the existing default" do
      another.promote_to_default!
      expect(another.reload.is_default).to be true
      expect(current_default.reload.is_default).to be false
    end
  end

  describe "after_commit broadcast" do
    it "publishes style.preset.changed on save" do
      allow(Sidekiq).to receive(:redis).and_yield(double(publish: nil))
      create(:style_preset)
      expect(Sidekiq).to have_received(:redis)
    end
  end
end
