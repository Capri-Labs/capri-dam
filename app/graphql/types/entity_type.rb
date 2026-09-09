# frozen_string_literal: true

module Types
  class EntityType < Types::BaseObject
    description <<~DESC
      A named thing the DAM knows about — a person, place, product, brand,
      campaign or event — as opposed to a tag, which is only a string that
      somebody once typed.

      The difference matters because two different people can share a name and
      one person can be written five different ways. An entity survives both:
      the alternate spellings become aliases, and a duplicate discovered later
      is merged into the survivor rather than deleted, so links made against the
      duplicate still resolve.
    DESC

    field :id,          ID,     null: false
    field :entity_type, String, null: false,
          description: "One of: person, place, product, brand, campaign, event."
    field :name,        String, null: false,
          description: "The canonical display name."
    field :slug,        String, null: false,
          description: "URL-safe name. Unique per type, not globally — the place " \
                       "'berlin' and the campaign 'berlin' may both hold it."
    field :reference,   String, null: false,
          description: "The `type:slug` form a search filter takes, e.g. `person:jane-doe`. " \
                       "Emitted by the server so a client never has to build it."
    field :description, String, null: true
    field :properties,  Types::JsonType, null: true,
          description: "Free-form structured attributes (role, coordinates, SKU, …)."
    field :external_ids, Types::JsonType, null: true,
          description: "Identifiers in other systems ({ wikidata:, pim_sku:, … }) — " \
                       "the hook for reconciling against an external authority."
    field :aliases,     [ String ], null: false,
          description: "Alternate spellings that resolve to this entity."
    field :canonical_id, ID, null: true,
          description: "Set when this entity was merged into another. Non-null means " \
                       "this record is a tombstone kept so old links keep working."
    field :asset_count, Integer, null: false,
          description: "Number of assets linked to this entity, confirmed or not."
    field :created_at,  GraphQL::Types::ISO8601DateTime, null: false
    field :updated_at,  GraphQL::Types::ISO8601DateTime, null: false

    def reference
      "#{object.entity_type}:#{object.slug}"
    end

    def aliases
      object.entity_aliases.order(:alias_text).pluck(:alias_text)
    end

    def asset_count
      object.asset_entities.count
    end

    def self.authorized?(object, context)
      super && context[:current_user].present?
    end
  end
end
