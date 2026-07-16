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

  # @!attribute [r] collection_policies
  #   @return [ActiveRecord::Associations::CollectionProxy<CollectionPolicy>]
  #   Group-scoped access grants — see {#accessible_by?}/{#editable_by?}/{#manageable_by?}.
  has_many :collection_policies, dependent: :destroy

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
  # Signed sharing
  # ---------------------------------------------------------------------------

  # Purpose tag scoped into every signed share token so a token minted for
  # sharing can never be replayed against a different signed-id use case (or
  # vice-versa) even if the underlying `secret_key_base` were ever reused.
  SHARE_TOKEN_PURPOSE = :collection_share

  # Default validity window for a freshly generated share link.
  SHARE_LINK_EXPIRY = 30.days

  # Returns +true+ when the collection is automatically populated by rules.
  #
  # @return [Boolean]
  def smart?
    collection_type == "smart"
  end

  # Mints a tamper-proof, time-boxed token (Rails' built-in signed-id
  # mechanism — HMAC-signed, no extra DB column/migration required) that can
  # be embedded in a public, unauthenticated share URL.
  #
  # @param expires_in [ActiveSupport::Duration]
  # @return [String] opaque signed token
  def generate_share_token(expires_in: SHARE_LINK_EXPIRY)
    signed_id(expires_in: expires_in, purpose: SHARE_TOKEN_PURPOSE)
  end

  # Resolves a share token back into the {Collection} it was minted for.
  # Returns +nil+ for a malformed, tampered, expired, or wrong-purpose token
  # (never raises), so callers can render a friendly "link expired" page.
  #
  # @param token [String]
  # @return [Collection, nil]
  def self.find_by_share_token(token)
    find_signed(token, purpose: SHARE_TOKEN_PURPOSE)
  end

  # Determines whether the given user is allowed to view this collection.
  #
  # Evaluation order:
  # 1. Admin or owner → +true+.
  # 2. Any {CollectionPolicy} row exists for this collection → access is
  #    governed *exclusively* by group policies from here on (an explicit
  #    +explicit_deny+ always wins; otherwise the user needs +view_access+,
  #    +edit_access+, or +admin_access+ via at least one of their groups).
  # 3. Otherwise, falls back to the legacy +allowed_groups+/+denied_groups+
  #    JSONB whitelist/blacklist (unchanged behavior for collections that
  #    haven't adopted the newer group-policy model yet).
  # 4. No constraints anywhere → +true+.
  #
  # @param user [User]
  # @return [Boolean]
  def accessible_by?(user)
    return true if user.admin? || user.id == self.user_id

    if collection_policies.exists?
      policies = collection_policies.where(user_group_id: user.effective_group_ids)
      return false if policies.any?(&:explicit_deny)

      return policies.any? { |p| p.view_access? || p.edit_access? || p.admin_access? }
    end

    user_group_names = user.user_groups.pluck(:name)

    if denied_groups.present? && denied_groups.any?
      return false if (denied_groups & user_group_names).any?
    end

    if allowed_groups.present? && allowed_groups.any?
      return (allowed_groups & user_group_names).any?
    end

    true
  end

  # Determines whether the given user may modify this workspace's contents
  # or properties (add/remove/pin assets, edit name/description/tags).
  #
  # Granted to: system admins/super-admins, the collection's own creator
  # (as long as no explicit group policy has been configured yet — see
  # class docs), and any user in a group with +edit_access+ or
  # +admin_access+ (unless explicitly denied).
  #
  # @param user [User]
  # @return [Boolean]
  def editable_by?(user)
    return true if system_admin?(user)
    return true if owner_bootstrap?(user)

    policies = collection_policies.where(user_group_id: user.effective_group_ids)
    return false if policies.any?(&:explicit_deny)

    policies.any? { |p| p.edit_access? || p.admin_access? }
  end

  # Determines whether the given user may manage this workspace's
  # governance-level configuration: smart rules, access policies, CDN purge.
  #
  # This is the "Collection Admin" tier — narrower than {#editable_by?} and
  # deliberately restricted to system admins/super-admins and users in a
  # group with +admin_access+ (the collection's creator retains this right
  # too, but only until an explicit {CollectionPolicy} has been configured —
  # see class docs).
  #
  # @param user [User]
  # @return [Boolean]
  def manageable_by?(user)
    return true if system_admin?(user)
    return true if owner_bootstrap?(user)

    policies = collection_policies.where(user_group_id: user.effective_group_ids)
    return false if policies.any?(&:explicit_deny)

    policies.any?(&:admin_access?)
  end

  # Archiving/deleting a workspace requires the same "Collection Admin" tier
  # as {#manageable_by?} — system admins, super-admins, and group-based
  # collection-admins (or the creator, until explicit policies exist).
  #
  # @param user [User]
  # @return [Boolean]
  def deletable_by?(user)
    manageable_by?(user)
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
  # System-level admins (regular or super) always bypass collection-level
  # governance entirely.
  def system_admin?(user)
    user.admin? || user.super_admin?
  end

  # @api private
  # The collection's creator retains full editable/manageable rights until
  # the workspace has been explicitly locked down with at least one
  # {CollectionPolicy} — at that point access is governed solely by group
  # policies, even for the original owner.
  def owner_bootstrap?(user)
    user.id == self.user_id && !collection_policies.exists?
  end

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
