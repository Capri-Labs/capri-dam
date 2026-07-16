# Represents a group of assets that share an identical SHA-256 checksum.
#
# Duplicate groups are created automatically by {DuplicateDetectionService}
# whenever a newly processed asset has a checksum that matches one or more
# existing assets.  Each group has a lifecycle:
#
#   pending → resolved (user kept all or deleted some copies)
#           → dismissed (user dismissed without action)
#
# Only +pending+ groups are shown in the Duplicate Manager UI.  At most
# {DISPLAY_LIMIT} groups are returned by the +pending+ scope to cap UI cost.
#
# @see DuplicateGroupAsset
# @see DuplicateDetectionService
# @see DuplicateDetectionWorker
class DuplicateGroup < ApplicationRecord
  # ---------------------------------------------------------------------------
  # Constants
  # ---------------------------------------------------------------------------

  # Maximum number of duplicate groups surfaced in the UI / API at once.
  DISPLAY_LIMIT = 100

  VALID_STATUSES = %w[pending resolved dismissed].freeze
  VALID_ACTIONS  = %w[kept_all deleted_duplicates].freeze

  # ---------------------------------------------------------------------------
  # Associations
  # ---------------------------------------------------------------------------

  has_many :duplicate_group_assets, foreign_key: :duplicate_group_id,
           dependent: :destroy, inverse_of: :duplicate_group

  has_many :assets, through: :duplicate_group_assets

  belongs_to :resolved_by, class_name: "User", foreign_key: :resolved_by_id,
             optional: true

  # ---------------------------------------------------------------------------
  # Validations
  # ---------------------------------------------------------------------------

  validates :checksum, presence: true, uniqueness: { scope: :status,
            message: "already has a pending duplicate group" },
            if: -> { status == "pending" }
  validates :status,            inclusion: { in: VALID_STATUSES }
  validates :resolution_action, inclusion: { in: VALID_ACTIONS }, allow_nil: true

  # ---------------------------------------------------------------------------
  # Scopes
  # ---------------------------------------------------------------------------

  scope :pending,   -> { where(status: "pending") }
  scope :resolved,  -> { where(status: "resolved") }
  scope :dismissed, -> { where(status: "dismissed") }

  # Returns at most DISPLAY_LIMIT pending groups, newest first.
  scope :for_display, -> {
    pending.order(created_at: :desc).limit(DISPLAY_LIMIT)
  }

  # ---------------------------------------------------------------------------
  # Instance methods
  # ---------------------------------------------------------------------------

  # Marks the group as resolved.
  #
  # @param action    [String] +"kept_all"+ or +"deleted_duplicates"+
  # @param user      [User]   the user performing the resolution
  # @return [Boolean]
  def resolve!(action:, user:)
    update!(
      status:            "resolved",
      resolution_action: action,
      resolved_at:       Time.current,
      resolved_by_id:    user.id,
    )
  end

  # Marks the group as dismissed (no action taken, group hidden from UI).
  #
  # @param user [User]
  # @return [Boolean]
  def dismiss!(user:)
    update!(
      status:         "dismissed",
      resolved_at:    Time.current,
      resolved_by_id: user.id,
    )
  end

  # Recomputes membership after a member {Asset} is soft-deleted (moved to
  # the Trash Bin) or restored, keeping the Duplicate Manager in sync
  # without a full rescan:
  #
  # * If fewer than 2 *active* (non-trashed) members remain, the group is
  #   auto-resolved (+status+ "resolved", +resolution_action+ left +nil+ so
  #   it's distinguishable from a user-driven resolution) and disappears
  #   from the pending list.
  # * If a previously auto-resolved group regains 2+ active members (an
  #   asset was restored from the bin), it is reopened to +pending+ so the
  #   user can review it again.
  #
  # Called from {Asset}'s +after_commit+ hook whenever +deleted_at+ changes.
  # Hard deletion is handled separately by {DuplicateGroupAsset#auto_resolve_group_if_depleted}.
  #
  # @return [void]
  def recalculate_active_membership!
    return if status == "dismissed"

    active_count = assets.merge(Asset.active).count

    if status == "pending"
      update!(total_count: active_count)
      if active_count < 2
        update!(status: "resolved", resolution_action: nil, resolved_at: Time.current)
      end
    elsif status == "resolved" && resolution_action.nil? && active_count >= 2
      update!(status: "pending", total_count: active_count, resolved_at: nil, resolved_by_id: nil)
    end
  end

  # Human-readable summary for notifications.
  #
  # @return [String]
  def summary
    "#{total_count} asset(s) share checksum #{checksum.first(12)}…"
  end
end
