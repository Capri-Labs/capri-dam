# frozen_string_literal: true

# The link: this asset stands in this stated relationship to this entity.
#
# WHY THE RELATIONSHIP IS PART OF THE RECORD
# ------------------------------------------
# Without it, an entity link says only "this asset has something to do with
# this person" — which is where tags already are. The relationship is what
# separates the photographer from the person in the frame, and it is the reason
# "everything shot by X" and "everything showing X" are different queries
# rather than one imprecise one.
#
# @see Entity
# @see Entities::Resolver
class AssetEntity < ApplicationRecord
  # The fixed vocabulary. Kept short and closed: an open predicate set cannot be
  # indexed usefully, cannot be offered in a UI, and cannot be reasoned about by
  # a rights or consent policy, because no policy can enumerate predicates it
  # has never seen.
  RELATIONSHIPS = %w[depicts shot_by belongs_to located_at mentions].freeze

  SOURCES = %w[manual tag_resolution ai].freeze

  # Not every relationship is meaningful for every type, and allowing the
  # nonsense ones is not harmless: "shot_by a campaign" would be accepted,
  # indexed, and then quietly returned by a query asking who took the picture.
  # A closed matrix is what makes the vocabulary mean something.
  VALID_TYPES = {
    "depicts"    => %w[person product place brand].freeze,
    "shot_by"    => %w[person].freeze,
    "belongs_to" => %w[campaign brand event].freeze,
    "located_at" => %w[place].freeze,
    # Deliberately unrestricted: a document or transcript can refer to anything,
    # and +mentions+ is the relationship that carries no claim about what is in
    # the frame — which is exactly why it needs no type constraint.
    "mentions"   => Entity::TYPES,
  }.freeze

  belongs_to :asset
  belongs_to :entity
  belongs_to :created_by,   class_name: "User", optional: true
  belongs_to :confirmed_by, class_name: "User", optional: true

  validates :relationship, inclusion: { in: RELATIONSHIPS }
  validates :source, inclusion: { in: SOURCES }
  validates :confidence, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 },
                         allow_nil: true
  validates :entity_id, uniqueness: {
    scope: [ :asset_id, :relationship ],
    message: "is already linked to this asset under that relationship",
  }

  validate :relationship_is_valid_for_entity_type
  validate :human_assertions_carry_no_confidence

  scope :confirmed,   -> { where.not(confirmed_at: nil) }
  scope :unconfirmed, -> { where(confirmed_at: nil) }
  scope :of_relationship, ->(rel) { where(relationship: rel) }

  # Links a person asserted, plus machine links a person has since agreed with.
  # This is the scope any policy decision should use: a proposal is not a fact.
  scope :asserted, -> { where(source: "manual").or(where.not(confirmed_at: nil)) }

  # @param relationship [String]
  # @return [Array<String>] the entity types the relationship may point at
  def self.types_for(relationship)
    VALID_TYPES.fetch(relationship.to_s, [])
  end

  # @return [Boolean] whether a person has stated or agreed with this link
  def asserted?
    source == "manual" || confirmed_at.present?
  end

  # Records human agreement with a machine-derived link.
  #
  # @param user [User, nil]
  # @return [Boolean]
  def confirm!(user: nil)
    update!(confirmed_at: Time.current, confirmed_by: user)
  end

  private

  def relationship_is_valid_for_entity_type
    return if entity.nil? || relationship.blank?
    return if self.class.types_for(relationship).include?(entity.entity_type)

    errors.add(:relationship, "'#{relationship}' cannot point at a #{entity.entity_type}")
  end

  def human_assertions_carry_no_confidence
    return unless source == "manual" && confidence.present?

    # A person does not have a confidence score. Storing one — even 1.0 — makes
    # a human assertion indistinguishable from a model that happened to be
    # certain, in exactly the query that needs to tell them apart.
    errors.add(:confidence, "is only meaningful for a machine-derived link")
  end
end
