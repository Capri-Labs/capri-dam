# frozen_string_literal: true

# A typed, identified thing the library refers to: a person, product, place,
# campaign, brand or event.
#
# Entities exist because +assets.properties["tags"]+ is an array of strings, and
# a string cannot say what it refers to. "Berlin" the city, "Berlin" the
# photographer and "Berlin" the campaign are one token there, so every question
# spanning them returns all three with no way to say which was meant.
#
# @see AssetEntity the link that states *how* an asset relates to an entity
# @see EntityAlias the other strings that mean this entity
# @see Entities::Resolver which builds links from existing tags
class Entity < ApplicationRecord
  # Fixed and deliberately short. Each type earns its place by changing what
  # questions become answerable, not by being a category somebody might want.
  TYPES = %w[person product place campaign brand event].freeze

  belongs_to :created_by, class_name: "User", optional: true

  # The record this one was merged into. Duplicates are kept rather than
  # deleted so that links made against the loser still resolve.
  belongs_to :canonical, class_name: "Entity", optional: true
  has_many :duplicates, class_name: "Entity", foreign_key: :canonical_id,
                        inverse_of: :canonical, dependent: :nullify

  has_many :entity_aliases, dependent: :destroy
  has_many :asset_entities, dependent: :destroy
  has_many :assets, through: :asset_entities

  validates :entity_type, inclusion: { in: TYPES }
  validates :name, presence: true, length: { maximum: 200 }
  validates :slug, presence: true,
                   uniqueness: { scope: :entity_type, message: "is already used by another %{model} of this type" },
                   format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/, message: "must be lowercase alphanumeric with hyphens" }

  before_validation :assign_slug

  scope :canonical_only, -> { where(canonical_id: nil) }
  scope :of_type, ->(type) { where(entity_type: type) }

  # Entities merged away are still valid targets of old links, but they must
  # never be *offered* — picking one would create a fresh link to a record
  # already known to be a duplicate.
  scope :selectable, -> { canonical_only.order(:name) }

  # @return [String] a slug candidate derived from a display name
  def self.slugify(name)
    name.to_s.parameterize.presence || "entity"
  end

  # Follows the merge chain to the record that survived.
  #
  # Chains are walked with a hard stop rather than recursion: the +canonical_id
  # <> id+ constraint prevents the one-step cycle, but nothing at the database
  # level prevents A→B→A, and an unbounded walk would hang the request rather
  # than return a wrong answer.
  #
  # @return [Entity]
  def canonical_entity
    seen = [ id ]
    node = self

    while node.canonical_id && !seen.include?(node.canonical_id)
      seen << node.canonical_id
      node = Entity.find_by(id: node.canonical_id) || node
      break if node.id == seen.last && node.canonical_id.nil?
    end

    node
  end

  # @return [Boolean] whether this record was merged into another
  def merged?
    canonical_id.present?
  end

  # Every string that should resolve to this entity, including its own name.
  # The name is included implicitly rather than duplicated into the alias table,
  # so renaming an entity cannot leave a stale alias behind that still resolves
  # to it under the old name.
  #
  # @return [Array<String>]
  def all_aliases
    ([ EntityAlias.normalise(name) ] + entity_aliases.pluck(:alias_text)).uniq
  end

  private

  def assign_slug
    self.slug = self.class.slugify(slug.presence || name) if slug.blank? || name_changed_without_slug?
  end

  def name_changed_without_slug?
    new_record? && slug.blank?
  end
end
