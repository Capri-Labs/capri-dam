# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entities::Merger do
  let(:survivor)  { create(:entity, :brand, name: "Volkswagen") }
  let(:duplicate) { create(:entity, :brand, name: "VW") }

  describe "links" do
    it "moves a link to the survivor rather than destroying it" do
      asset = create(:asset)
      link = create(:asset_entity, asset: asset, entity: duplicate, relationship: "depicts")

      result = described_class.call(duplicate: duplicate, canonical: survivor)

      expect(result.links_moved).to eq(1)
      expect(link.reload.entity).to eq(survivor)
    end

    it "collapses a claim both entities already carried" do
      asset = create(:asset)
      create(:asset_entity, asset: asset, entity: survivor, relationship: "depicts")
      create(:asset_entity, asset: asset, entity: duplicate, relationship: "depicts")

      result = described_class.call(duplicate: duplicate, canonical: survivor)

      expect(result.links_discarded).to eq(1)
      expect(asset.asset_entities.count).to eq(1)
    end

    it "never demotes a confirmed link to a proposal when collapsing" do
      asset = create(:asset)
      kept = create(:asset_entity, :from_ai, asset: asset, entity: survivor, relationship: "depicts")
      create(:asset_entity, asset: asset, entity: duplicate, relationship: "depicts", source: "manual")

      described_class.call(duplicate: duplicate, canonical: survivor)

      expect(kept.reload.source).to eq("manual")
      expect(kept).to be_asserted
    end

    it "keeps the survivor's assertion when the duplicate was only a guess" do
      asset = create(:asset)
      kept = create(:asset_entity, asset: asset, entity: survivor, relationship: "depicts", source: "manual")
      create(:asset_entity, :from_ai, asset: asset, entity: duplicate, relationship: "depicts")

      described_class.call(duplicate: duplicate, canonical: survivor)

      expect(kept.reload.source).to eq("manual")
    end
  end

  describe "aliases" do
    it "adopts the duplicate's name so the string that caused it still resolves" do
      described_class.call(duplicate: duplicate, canonical: survivor)

      expect(EntityAlias.candidates_for("VW")).to contain_exactly(survivor)
    end

    it "carries the duplicate's own aliases across" do
      create(:entity_alias, entity: duplicate, alias_text: "volkswagen ag")

      described_class.call(duplicate: duplicate, canonical: survivor)

      expect(EntityAlias.candidates_for("Volkswagen AG")).to contain_exactly(survivor)
    end

    it "does not duplicate an alias the survivor already had" do
      create(:entity_alias, entity: survivor, alias_text: "vw")
      create(:entity_alias, entity: duplicate, alias_text: "vw")

      described_class.call(duplicate: duplicate, canonical: survivor)

      expect(survivor.entity_aliases.where(alias_text: "vw").count).to eq(1)
    end
  end

  describe "the duplicate afterwards" do
    it "is kept and points at the survivor, so old references still resolve" do
      described_class.call(duplicate: duplicate, canonical: survivor)

      expect(duplicate.reload).to be_persisted
      expect(duplicate.canonical_entity).to eq(survivor)
    end

    it "stops being offered" do
      described_class.call(duplicate: duplicate, canonical: survivor)

      expect(Entity.selectable).not_to include(duplicate)
    end
  end

  describe "refusals" do
    it "refuses to merge an entity into itself" do
      expect { described_class.call(duplicate: survivor, canonical: survivor) }
        .to raise_error(ArgumentError, /into itself/)
    end

    it "refuses to merge across types, which would reclassify every link" do
      place = create(:entity, :place, name: "Wolfsburg")

      expect { described_class.call(duplicate: place, canonical: survivor) }
        .to raise_error(ArgumentError, /Cannot merge a place into a brand/)
    end

    it "refuses to merge into an entity that was itself merged away" do
      already_merged = create(:entity, :brand, name: "VAG", canonical: survivor)

      expect { described_class.call(duplicate: duplicate, canonical: already_merged) }
        .to raise_error(ArgumentError, /itself merged away/)
    end

    it "leaves nothing half-applied when a merge fails" do
      asset = create(:asset)
      create(:asset_entity, asset: asset, entity: duplicate, relationship: "depicts")
      allow(EntityAlias).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(EntityAlias.new))

      expect { described_class.call(duplicate: duplicate, canonical: survivor) }
        .to raise_error(ActiveRecord::RecordInvalid)

      expect(duplicate.reload.canonical_id).to be_nil
      expect(asset.asset_entities.first.entity).to eq(duplicate)
    end
  end
end
