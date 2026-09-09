# frozen_string_literal: true

require "rails_helper"

# The entity half of the query compiler. Kept in its own file because it is the
# one field type that compiles to a correlated subquery over another table
# rather than an expression over `assets`.
RSpec.describe Search::QueryCompiler, "entity fields" do
  def ids(ast)
    described_class.new(ast).apply(Asset.all).pluck(:id)
  end

  def filter(field, operator, value = nil)
    node = { "field" => field, "operator" => operator }
    node["value"] = value unless value.nil?
    node
  end

  # The motivating case, stated exactly: three different things that a plain
  # tag would render as the single string "berlin".
  let!(:berlin_place)  { create(:entity, entity_type: "place",  name: "Berlin") }
  let!(:berlin_person) { create(:entity, entity_type: "person", name: "Berlin") }
  let!(:berlin_campaign) { create(:entity, entity_type: "campaign", name: "Berlin") }

  let!(:on_location) { create(:asset, title: "Shot in Berlin") }
  let!(:by_berlin)   { create(:asset, title: "Taken by Berlin") }
  let!(:campaign_asset) { create(:asset, title: "Berlin campaign hero") }
  let!(:unrelated)   { create(:asset, title: "Nothing to do with it") }

  before do
    create(:asset_entity, asset: on_location, entity: berlin_place, relationship: "located_at")
    create(:asset_entity, asset: by_berlin, entity: berlin_person, relationship: "shot_by")
    create(:asset_entity, asset: campaign_asset, entity: berlin_campaign, relationship: "belongs_to")
  end

  describe "the ambiguity this exists to remove" do
    it "tells the place from the photographer from the campaign" do
      expect(ids(filter("located_at", "has_any", [ "place:berlin" ]))).to contain_exactly(on_location.id)
      expect(ids(filter("shot_by", "has_any", [ "person:berlin" ]))).to contain_exactly(by_berlin.id)
      expect(ids(filter("belongs_to", "has_any", [ "campaign:berlin" ]))).to contain_exactly(campaign_asset.id)
    end

    it "rejects a bare slug instead of guessing which Berlin was meant" do
      expect { ids(filter("shot_by", "has_any", [ "berlin" ])) }
        .to raise_error(Search::QueryCompiler::InvalidQuery, /ambiguous/)
    end

    it "names the qualified form in the error, rather than only refusing" do
      expect { ids(filter("shot_by", "has_any", [ "berlin" ])) }
        .to raise_error(/person:berlin/)
    end
  end

  describe "references" do
    it "accepts an entity id" do
      expect(ids(filter("located_at", "has_any", [ berlin_place.id ]))).to contain_exactly(on_location.id)
    end

    it "matches nothing for an unknown entity rather than everything" do
      expect(ids(filter("located_at", "has_any", [ "place:atlantis" ]))).to be_empty
    end

    it "still finds assets after the entity they name has been merged away" do
      survivor = create(:entity, entity_type: "place", name: "Berlin, Germany")
      Entities::Merger.call(duplicate: berlin_place, canonical: survivor)

      expect(ids(filter("located_at", "has_any", [ berlin_place.id ]))).to contain_exactly(on_location.id)
    end
  end

  describe "the relationship-agnostic field" do
    it "matches a link under any relationship" do
      expect(ids(filter("entity", "has_any", [ "person:berlin" ]))).to contain_exactly(by_berlin.id)
    end

    it "reports presence of any link at all" do
      expect(ids(filter("entity", "present")))
        .to contain_exactly(on_location.id, by_berlin.id, campaign_asset.id)
    end

    it "reports absence" do
      expect(ids(filter("entity", "blank"))).to contain_exactly(unrelated.id)
    end
  end

  describe "operators" do
    let!(:product) { create(:entity, entity_type: "product", name: "Acme Runner") }
    let!(:brand)   { create(:entity, entity_type: "brand", name: "Acme") }
    let!(:both)    { create(:asset, title: "Product on brand backdrop") }

    before do
      create(:asset_entity, asset: both, entity: product, relationship: "depicts")
      create(:asset_entity, asset: both, entity: brand, relationship: "depicts")
      create(:asset_entity, asset: on_location, entity: product, relationship: "depicts")
    end

    it "has_any matches either" do
      expect(ids(filter("depicts", "has_any", [ "product:acme-runner", "brand:acme" ])))
        .to contain_exactly(both.id, on_location.id)
    end

    it "has_all requires every one" do
      expect(ids(filter("depicts", "has_all", [ "product:acme-runner", "brand:acme" ])))
        .to contain_exactly(both.id)
    end

    it "none_of excludes the named entities but keeps assets with no links at all" do
      result = ids(filter("depicts", "none_of", [ "product:acme-runner" ]))

      expect(result).to include(unrelated.id, by_berlin.id)
      expect(result).not_to include(both.id, on_location.id)
    end

    it "present is scoped to the relationship, not to links in general" do
      expect(ids(filter("depicts", "present"))).to contain_exactly(both.id, on_location.id)
    end
  end

  describe "composition with the rest of the AST" do
    it "answers the question the phase was written for" do
      product  = create(:entity, entity_type: "product", name: "Acme Runner")
      campaign = create(:entity, entity_type: "campaign", name: "Spring Launch")
      hit = create(:asset, title: "Spring hero", usage_terms: "royalty_free")
      miss = create(:asset, title: "Spring outtake", usage_terms: "internal_only")

      [ hit, miss ].each do |asset|
        create(:asset_entity, asset: asset, entity: product, relationship: "depicts")
        create(:asset_entity, asset: asset, entity: campaign, relationship: "belongs_to")
      end

      # "every asset featuring product X from campaign Y that we may still publish"
      ast = {
        "op" => "and",
        "children" => [
          filter("depicts", "has_any", [ "product:acme-runner" ]),
          filter("belongs_to", "has_any", [ "campaign:spring-launch" ]),
          { "field" => "usage_terms", "operator" => "eq", "value" => "royalty_free" },
        ],
      }

      expect(ids(ast)).to contain_exactly(hit.id)
    end

    it "does not multiply rows, which a join would have" do
      extra = create(:entity, entity_type: "place", name: "Mitte")
      create(:asset_entity, asset: on_location, entity: extra, relationship: "located_at")

      expect(ids(filter("located_at", "present")).tally.values).to all(eq(1))
    end
  end

  describe "the field registry" do
    it "offers set operators for entity fields, not equality" do
      expect(Search::FieldRegistry.operators_for(:entity))
        .to contain_exactly("has_any", "has_all", "none_of", "present", "blank")
    end

    it "publishes one field per relationship so the builder can offer them" do
      names = Search::FieldRegistry.definitions.select { |f| f.type == :entity }.map(&:name)

      expect(names).to include(*AssetEntity::RELATIONSHIPS)
      expect(names).to include("entity")
    end
  end
end
