# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entities::Resolver do
  def asset_with_tags(*tags)
    create(:asset, properties: { "tags" => tags })
  end

  describe "matching" do
    it "links a tag that names exactly one entity" do
      create(:entity, :product, name: "Acme Runner")
      asset = asset_with_tags("acme runner")

      outcome = described_class.call(asset)

      expect(outcome.linked.size).to eq(1)
      expect(asset.asset_entities.first.relationship).to eq("depicts")
      expect(asset.asset_entities.first.source).to eq("tag_resolution")
    end

    it "matches through an alias, which is where most of the library's vocabulary lives" do
      brand = create(:entity, :brand, name: "Volkswagen")
      create(:entity_alias, entity: brand, alias_text: "VW")
      asset = asset_with_tags("vw")

      expect(described_class.call(asset).linked.size).to eq(1)
      expect(asset.asset_entities.first.entity).to eq(brand)
    end

    it "reports a tag that names nothing" do
      asset = asset_with_tags("sunset")

      expect(described_class.call(asset).unmatched).to eq([ "sunset" ])
    end

    it "ignores case and surrounding whitespace" do
      create(:entity, :place, name: "Berlin")
      asset = asset_with_tags("  BERLIN ")

      expect(described_class.call(asset).linked.size).to eq(1)
    end
  end

  describe "ambiguity" do
    it "refuses to choose when a tag names several entities" do
      create(:entity, :place, name: "Berlin")
      create(:entity, :person, name: "Berlin")
      asset = asset_with_tags("berlin")

      outcome = described_class.call(asset)

      expect(outcome.linked).to be_empty
      expect(outcome.ambiguous.size).to eq(1)
      expect(outcome.ambiguous.first[:candidates].map(&:entity_type)).to contain_exactly("place", "person")
      expect(asset.asset_entities).to be_empty
    end
  end

  describe "the relationship it infers" do
    it "reads a place as where the asset was made" do
      create(:entity, :place, name: "Berlin")
      asset = asset_with_tags("berlin")
      described_class.call(asset)

      expect(asset.asset_entities.first.relationship).to eq("located_at")
    end

    it "reads a campaign as membership" do
      create(:entity, :campaign, name: "Spring Launch")
      asset = asset_with_tags("spring launch")
      described_class.call(asset)

      expect(asset.asset_entities.first.relationship).to eq("belongs_to")
    end

    it "never infers shot_by, because a tag cannot tell the photographer from the subject" do
      create(:entity, :person, name: "Jane Doe")
      asset = asset_with_tags("jane doe")
      described_class.call(asset)

      expect(asset.asset_entities.first.relationship).to eq("depicts")
      expect(AssetEntity.of_relationship("shot_by")).to be_empty
    end
  end

  describe "what it never does" do
    it "leaves the asset's tags exactly as they were" do
      create(:entity, :place, name: "Berlin")
      asset = asset_with_tags("berlin", "sunset")

      expect { described_class.call(asset) }
        .not_to change { asset.reload.properties["tags"] }
    end

    it "creates only unconfirmed links, so a string match cannot become an assertion" do
      create(:entity, :place, name: "Berlin")
      asset = asset_with_tags("berlin")

      described_class.call(asset)

      expect(asset.asset_entities.first).not_to be_asserted
      expect(AssetEntity.asserted).to be_empty
    end

    it "does not demote a confirmed link when re-run" do
      place = create(:entity, :place, name: "Berlin")
      asset = asset_with_tags("berlin")
      link = create(:asset_entity, asset: asset, entity: place, relationship: "located_at",
                                   source: "manual", confirmed_at: Time.current)

      described_class.call(asset)

      expect(link.reload.source).to eq("manual")
      expect(link.confirmed_at).to be_present
      expect(asset.asset_entities.count).to eq(1)
    end

    it "writes nothing on a dry run" do
      create(:entity, :place, name: "Berlin")
      asset = asset_with_tags("berlin")

      outcome = described_class.call(asset, dry_run: true)

      expect(outcome.linked.size).to eq(1)
      expect(AssetEntity.count).to eq(0)
    end

    it "never offers an entity that was merged away" do
      survivor = create(:entity, :brand, name: "Volkswagen")
      create(:entity, :brand, name: "VW", canonical: survivor)
      asset = asset_with_tags("vw")

      outcome = described_class.call(asset)

      expect(outcome.linked).to be_empty
      expect(outcome.unmatched).to eq([ "vw" ])
    end
  end
end
