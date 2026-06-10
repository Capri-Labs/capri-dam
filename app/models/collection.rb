class Collection < ApplicationRecord
  store_accessor :properties, :tags, :allowed_groups, :denied_groups
  # Associations
  belongs_to :user
  has_many :collection_assets, dependent: :destroy
  has_one :collection_rule, dependent: :destroy
  has_many :assets, through: :collection_assets

  # Validations
  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :uuid, presence: true, uniqueness: true
  validates :collection_type, inclusion: { in: %w[manual smart] }

  # Callbacks
  before_validation :generate_uuid, on: :create
  before_validation :generate_slug, on: :create
  after_initialize :set_default_properties, if: :new_record?

  # Scopes for the CollectionBoard dashboard
  # Enforces Time-to-Live (TTL) to auto-archive expired campaigns
  scope :active, -> { where(deleted_at: nil).where('expires_at IS NULL OR expires_at > ?', Time.current) }
  scope :smart, -> { where(collection_type: 'smart') }
  scope :manual, -> { where(collection_type: 'manual') }

  def smart?
    collection_type == 'smart'
  end

  # ==========================================
  # AI & ABAC (Attribute-Based Access Control)
  # ==========================================

  def accessible_by?(user)
    # 1. System Overrides
    return true if user.admin? || user.id == self.user_id

    # Safely extract user's group names (e.g., ["EMEA Marketing", "Global Admin"])
    # Assuming user.user_groups exists from your earlier Group/Folder policy artifacts
    user_group_names = user.user_groups.pluck(:name)

    # 2. Explicit Deny (Blacklist) - Always evaluated first
    # If the user belongs to ANY denied group, instantly block access.
    if denied_groups.present? && denied_groups.any?
      return false if (denied_groups & user_group_names).any?
    end

    # 3. Explicit Allow (Whitelist)
    # If a whitelist exists, the user MUST be in one of the groups.
    if allowed_groups.present? && allowed_groups.any?
      return (allowed_groups & user_group_names).any?
    end

    # 4. Default Allow (If no whitelist or blacklist exists, it's globally visible)
    true
  end

  # Expose the asset count for the JSON serializer
  def assets_count
    collection_assets.count
  end

  # Automated Usage Rights Compliance Sweep
  def compliance_violations
    violations = []

    # Define what constitutes a "Public" or "External" workspace
    is_externally_accessible = Array(allowed_groups).empty? || Array(allowed_groups).include?("External Agencies")

    assets.find_each do |asset|
      props = asset.properties || {}
      usage = props['usage_terms'] || 'Internal Use Only'

      # Rule 1: Internal assets inside external workspaces
      if is_externally_accessible && usage == 'Internal Use Only'
        violations << {
          asset_id: asset.id,
          title: asset.title || asset.original_filename,
          reason: "Asset is restricted to 'Internal Use Only' but workspace allows external access."
        }
      end

      # Rule 2: Temporal Expiration (Asset license expires before campaign ends)
      if props['license_expires_at'].present? && self.expires_at.present?
        if Time.zone.parse(props['license_expires_at']) < self.expires_at
          violations << {
            asset_id: asset.id,
            title: asset.title || asset.original_filename,
            reason: "Asset license expires before the campaign workspace TTL finishes."
          }
        end
      end
    end

    violations
  end

  private

  def set_default_properties
    self.properties ||= {}
    self.tags ||= []
    self.allowed_groups ||= []
    self.denied_groups ||= []
  end

  def generate_uuid
    self.uuid ||= SecureRandom.uuid
  end

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