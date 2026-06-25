# A named grouping of {Asset}s used for campaign management and content delivery.
#
# Collections can be either **manual** (assets curated by a user) or **smart**
# (assets automatically populated by {SmartCollectionRouterWorker} based on
# semantic vector proximity defined in a {CollectionRule}).
#
# == Access Control (ABAC)
#
# Each collection stores +allowed_groups+ (whitelist) and +denied_groups+
# (blacklist) arrays inside its +properties+ JSONB column.  The
# {#accessible_by?} method enforces a three-tier evaluation:
#
# 1. Admin / owner → always allowed.
# 2. Denied groups → instant deny (evaluated before allow).
# 3. Allowed groups (whitelist) → user must be in at least one.
# 4. No constraints → globally visible.
#
# == TTL / Expiry
#
# Collections support an +expires_at+ timestamp for time-boxed campaigns.  The
# +active+ scope automatically filters out expired collections so stale
# campaigns are invisible to consumers without any manual cleanup.
#
# == Compliance checks
#
# {#compliance_violations} scans every asset in the collection and reports
# usage-rights violations (internal assets in external workspaces, expired
# licenses, etc.).
#
# @see CollectionRule
# @see CollectionAsset
# @see SmartCollectionRouterWorker
class Collection < ApplicationRecord
  store_accessor :properties, :tags, :allowed_groups, :denied_groups

  # ---------------------------------------------------------------------------
  # Associations
  # ---------------------------------------------------------------------------

  # @!attribute [r] user
  #   @return [User] the owner who created the collection
  belongs_to :user

  # @!attribute [r] collection_assets
  #   @return [ActiveRecord::Associations::CollectionProxy<CollectionAsset>]
  has_many :collection_assets, dependent: :destroy

  # @!attribute [r] collection_rule
  #   @return [CollectionRule, nil] the smart-routing rule for auto-population
  has_one :collection_rule, dependent: :destroy

  # @!attribute [r] assets
  #   @return [ActiveRecord::Associations::CollectionProxy<Asset>]
  has_many :assets, through: :collection_assets

  # ---------------------------------------------------------------------------
  # Validations
  # ---------------------------------------------------------------------------

  validates :name,            presence: true
  validates :slug,            presence: true, uniqueness: true
  validates :uuid,            presence: true, uniqueness: true
  validates :collection_type, inclusion: { in: %w[manual smart] }

  # ---------------------------------------------------------------------------
  # Callbacks
  # ---------------------------------------------------------------------------

  before_validation :generate_uuid, on: :create
  before_validation :generate_slug, on: :create
  after_initialize  :set_default_properties, if: :new_record?

  # ---------------------------------------------------------------------------
  # Scopes
  # ---------------------------------------------------------------------------

  # Non-deleted collections that have not yet exceeded their expiry date.
  # @return [ActiveRecord::Relation]
  scope :active, -> { where(deleted_at: nil).where("expires_at IS NULL OR expires_at > ?", Time.current) }

  # @return [ActiveRecord::Relation]
  scope :smart,  -> { where(collection_type: "smart") }

  # @return [ActiveRecord::Relation]
  scope :manual, -> { where(collection_type: "manual") }

  # ---------------------------------------------------------------------------
  # Public instance methods
  # ---------------------------------------------------------------------------

  # Returns +true+ when the collection is automatically populated by rules.
  #
  # @return [Boolean]
  def smart?
    collection_type == "smart"
  end

  # Determines whether the given user is allowed to view this collection.
  #
  # Evaluation order:
  # 1. Admin or owner → +true+.
  # 2. User belongs to a denied group → +false+.
  # 3. Whitelist exists and user is in it → +true+.
  # 4. No constraints → +true+.
  #
  # @param user [User]
  # @return [Boolean]
  def accessible_by?(user)
    return true if user.admin? || user.id == self.user_id

    user_group_names = user.user_groups.pluck(:name)

    if denied_groups.present? && denied_groups.any?
      return false if (denied_groups & user_group_names).any?
    end

    if allowed_groups.present? && allowed_groups.any?
      return (allowed_groups & user_group_names).any?
    end

    true
  end

  # Returns the number of assets currently in this collection.
  #
  # @return [Integer]
  def assets_count
    collection_assets.count
  end

  # Scans every asset for usage-rights compliance violations.
  #
  # Current rules checked:
  # * Internal-only assets inside externally accessible collections.
  # * Assets whose license expiry predates the collection's own +expires_at+.
  #
  # @return [Array<Hash>] each entry has +:asset_id+, +:title+, +:reason+
  def compliance_violations
    violations = []

    is_externally_accessible = Array(allowed_groups).empty? ||
                               Array(allowed_groups).include?("External Agencies")

    assets.find_each do |asset|
      props = asset.properties || {}
      usage = props["usage_terms"] || "Internal Use Only"

      if is_externally_accessible && usage == "Internal Use Only"
        violations << {
          asset_id: asset.id,
          title:    asset.title || asset.original_filename,
          reason:   "Asset is restricted to 'Internal Use Only' but workspace allows external access.",
        }
      end

      if props["license_expires_at"].present? && self.expires_at.present?
        if Time.zone.parse(props["license_expires_at"]) < self.expires_at
          violations << {
            asset_id: asset.id,
            title:    asset.title || asset.original_filename,
            reason:   "Asset license expires before the campaign workspace TTL finishes.",
          }
        end
      end
    end

    violations
  end

  private

  # @api private
  def set_default_properties
    self.properties    ||= {}
    self.tags          ||= []
    self.allowed_groups ||= []
    self.denied_groups  ||= []
  end

  # @api private
  def generate_uuid
    self.uuid ||= SecureRandom.uuid
  end

  # Generates a URL-safe, unique slug from +name+, appending an incrementing
  # suffix if a collision is detected.
  # @api private
  def generate_slug
    if name.present? && slug.blank?
      base_slug = name.parameterize
      self.slug = base_slug

      count = 1
      while Collection.exists?(slug: self.slug)
        self.slug = "#{base_slug}-#{count}"
        count += 1
      end
    end
  end
end
