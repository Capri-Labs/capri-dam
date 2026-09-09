# frozen_string_literal: true

require "rails_helper"

RSpec.describe AssetEntity do
  let(:asset) { create(:asset) }

  describe "the relationship matrix" do
    it "allows a person to be the photographer" do
      person = create(:entity, :person)

      expect(build(:asset_entity, asset: asset, entity: person, relationship: "shot_by")).to be_valid
    end

    it "refuses to say a campaign took the photograph" do
      campaign = create(:entity, :campaign)
      link = build(:asset_entity, asset: asset, entity: campaign, relationship: "shot_by")

      expect(link).not_to be_valid
      expect(link.errors[:relationship].first).to include("cannot point at a campaign")
    end

    it "refuses to place an asset at a product" do
      product = create(:entity, :product)

      expect(build(:asset_entity, asset: asset, entity: product, relationship: "located_at")).not_to be_valid
    end

    it "lets mentions point at anything, because a document can refer to anything" do
      Entity::TYPES.each do |type|
        entity = create(:entity, entity_type: type, name: "Mentioned #{type}")

        expect(build(:asset_entity, asset: asset, entity: entity, relationship: "mentions")).to be_valid
      end
    end
  end

  describe "uniqueness" do
    it "allows the same entity twice under different relationships" do
      person = create(:entity, :person)
      create(:asset_entity, asset: asset, entity: person, relationship: "shot_by")

      expect(build(:asset_entity, asset: asset, entity: person, relationship: "depicts")).to be_valid
    end

    it "rejects the same claim twice" do
      person = create(:entity, :person)
      create(:asset_entity, asset: asset, entity: person, relationship: "depicts")

      expect(build(:asset_entity, asset: asset, entity: person, relationship: "depicts")).not_to be_valid
    end
  end

  describe "confidence" do
    it "refuses a confidence score on a human assertion" do
      link = build(:asset_entity, asset: asset, source: "manual", confidence: 1.0)

      expect(link).not_to be_valid
      expect(link.errors[:confidence].first).to include("machine-derived")
    end

    it "accepts one on a machine-derived link" do
      expect(build(:asset_entity, :from_ai, asset: asset)).to be_valid
    end

    it "rejects a value outside 0..1" do
      expect(build(:asset_entity, asset: asset, source: "ai", confidence: 1.4)).not_to be_valid
    end
  end

  describe "#asserted?" do
    it "is true for a human statement" do
      expect(create(:asset_entity, asset: asset)).to be_asserted
    end

    it "is false for an unreviewed proposal" do
      expect(create(:asset_entity, :from_ai, asset: asset)).not_to be_asserted
    end

    it "becomes true once a person agrees" do
      link = create(:asset_entity, :from_ai, asset: asset)

      expect { link.confirm!(user: create(:user)) }.to change(link, :asserted?).to(true)
      expect(link.confirmed_by).to be_present
    end
  end

  describe ".asserted" do
    it "returns human statements and confirmed proposals, never bare guesses" do
      manual    = create(:asset_entity, asset: asset, entity: create(:entity, name: "A"))
      confirmed = create(:asset_entity, :from_ai, :confirmed, asset: asset, entity: create(:entity, name: "B"))
      create(:asset_entity, :from_ai, asset: asset, entity: create(:entity, name: "C"))

      expect(described_class.asserted).to contain_exactly(manual, confirmed)
    end
  end
end
