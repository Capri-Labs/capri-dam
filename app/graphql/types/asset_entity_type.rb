# frozen_string_literal: true

module Types
  class AssetEntityType < Types::BaseObject
    description <<~DESC
      A statement that an asset relates to an entity in a particular way.

      The relationship is the point. A tag reading "jane-doe" cannot tell you
      whether Jane is in the photograph or took it, and those two facts lead to
      opposite answers when a consent or a credit question is asked later.
    DESC

    field :id,     ID, null: false
    field :entity, Types::EntityType, null: false
    field :relationship, String, null: false,
          description: "One of: depicts, shot_by, belongs_to, located_at, mentions. " \
                       "The vocabulary is closed so it can be indexed, offered in a UI " \
                       "and reasoned about by a policy."
    field :source, String, null: false,
          description: "Where the claim came from: manual, tag_resolution or ai."
    field :confidence, Float, null: true,
          description: "Machine-derived links only. A person does not get a confidence score, " \
                       "and giving one 1.0 would make the two indistinguishable."
    field :asserted, Boolean, null: false,
          description: "True when a person stated or confirmed this link. This — not `source` — " \
                       "is the field any consent or rights decision should read: an unconfirmed " \
                       "link is a proposal about identity, not a finding."
    field :confirmed_at, GraphQL::Types::ISO8601DateTime, null: true
    field :created_at,   GraphQL::Types::ISO8601DateTime, null: false

    def asserted
      object.asserted?
    end

    def self.authorized?(object, context)
      super && context[:current_user].present?
    end
  end
end
