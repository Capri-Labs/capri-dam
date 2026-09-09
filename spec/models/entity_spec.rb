# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entity do
  describe "identity" do
    it "lets the same slug exist under different types, which is the whole point" do
      place  = create(:entity, entity_type: "place", name: "Berlin")
      person = create(:entity, entity_type: "person", name: "Berlin")

      expect(place.slug).to eq("berlin")
      expect(person.slug).to eq("berlin")
    end

    it "rejects a duplicate slug within one type" do
      create(:entity, entity_type: "place", name: "Berlin")

      expect(build(:entity, entity_type: "place", name: "Berlin")).not_to be_valid
    end

    it "derives a slug from the name" do
      expect(create(:entity, name: "Jane Q. Doe").slug).to eq("jane-q-doe")
    end

    it "falls back rather than saving a blank slug for a name with no slug characters" do
      expect(create(:entity, name: "!!!").slug).to eq("entity")
    end

    it "rejects an unknown type" do
      expect(build(:entity, entity_type: "spaceship")).not_to be_valid
    end

    it "rejects a hand-supplied slug that is not slug-shaped" do
      expect(build(:entity, slug: "Not A Slug")).not_to be_valid
    end
  end

  describe "#canonical_entity" do
    it "returns itself when nothing was merged" do
      entity = create(:entity)

      expect(entity.canonical_entity).to eq(entity)
    end

    it "follows a merge chain to the survivor" do
      survivor = create(:entity, name: "Volkswagen", entity_type: "brand")
      middle   = create(:entity, name: "VW AG", entity_type: "brand", canonical: survivor)
      duplicate = create(:entity, name: "VW", entity_type: "brand", canonical: middle)

      expect(duplicate.canonical_entity).to eq(survivor)
    end

    it "terminates on a cycle rather than hanging the request" do
      a = create(:entity, name: "A", entity_type: "brand")
      b = create(:entity, name: "B", entity_type: "brand", canonical: a)
      a.update_columns(canonical_id: b.id)

      expect { Timeout.timeout(5) { a.canonical_entity } }.not_to raise_error
    end
  end

  describe "#all_aliases" do
    it "includes the entity's own name without duplicating it into the table" do
      entity = create(:entity, name: "Volkswagen", entity_type: "brand")
      create(:entity_alias, entity: entity, alias_text: "VW")

      expect(entity.all_aliases).to contain_exactly("volkswagen", "vw")
    end
  end

  describe ".selectable" do
    it "excludes entities that were merged away, so nobody links to a known duplicate" do
      survivor = create(:entity, name: "Volkswagen", entity_type: "brand")
      create(:entity, name: "VW", entity_type: "brand", canonical: survivor)

      expect(described_class.selectable).to contain_exactly(survivor)
    end
  end
end
