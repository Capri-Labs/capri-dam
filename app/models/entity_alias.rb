# frozen_string_literal: true

# An alternate string that means a given entity.
#
# This is the bridge between the free-text tag vocabulary the library already
# has and the typed entities it is growing. "VW", "Volkswagen" and
# "volkswagen ag" are one brand; without somewhere to record that, resolution
# could only ever match an entity's own name, and the entity layer would
# describe the tidy half of the library while ignoring the half that needs it.
#
# @see Entities::Resolver
class EntityAlias < ApplicationRecord
  SOURCES = %w[manual tag import].freeze

  belongs_to :entity

  validates :alias_text, presence: true, length: { maximum: 200 },
                         uniqueness: { scope: :entity_id, message: "is already an alias for this entity" }
  validates :source, inclusion: { in: SOURCES }

  before_validation :normalise_alias_text

  # Aliases are stored normalised so lookup is an index probe rather than a
  # function scan. Case and surrounding punctuation carry no meaning here —
  # "Volkswagen", "volkswagen" and " Volkswagen " are the same claim — while
  # internal spacing does, so it is collapsed rather than stripped.
  #
  # @param value [String, nil]
  # @return [String]
  def self.normalise(value)
    value.to_s.unicode_normalize(:nfkc).downcase.gsub(/\s+/, " ").strip
  end

  # Every entity an incoming string could mean.
  #
  # Returns a collection rather than a record on purpose. An alias matching
  # several entities is the ambiguity this feature exists to surface, and a
  # +find_by+ here would pick one arbitrarily — reintroducing, one layer up,
  # exactly the silent collapse that plain tags already perform.
  #
  # @param value [String]
  # @return [ActiveRecord::Relation<Entity>]
  def self.candidates_for(value)
    normalised = normalise(value)
    return Entity.none if normalised.blank?

    Entity
      .canonical_only
      .where(id: where(alias_text: normalised).select(:entity_id))
      .or(Entity.canonical_only.where("lower(name) = ?", normalised))
      .distinct
  end

  private

  def normalise_alias_text
    self.alias_text = self.class.normalise(alias_text)
  end
end
