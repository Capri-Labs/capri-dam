# Join record connecting a {DuplicateGroup} to one of its member {Asset}s.
#
# The +is_original+ flag is +true+ for the earliest-created asset in the
# group (i.e. the one with the oldest +created_at+).  The UI uses this hint
# to suggest which copy to keep.
#
# @see DuplicateGroup
# @see Asset
class DuplicateGroupAsset < ApplicationRecord
  # ---------------------------------------------------------------------------
  # Associations
  # ---------------------------------------------------------------------------

  belongs_to :duplicate_group, foreign_key: :duplicate_group_id,
             inverse_of: :duplicate_group_assets

  belongs_to :asset, foreign_key: :asset_id, primary_key: :id

  # ---------------------------------------------------------------------------
  # Validations
  # ---------------------------------------------------------------------------

  validates :duplicate_group_id, presence: true
  validates :asset_id, presence: true,
            uniqueness: { scope: :duplicate_group_id,
                          message: "is already a member of this duplicate group" }

  # ---------------------------------------------------------------------------
  # Callbacks
  # ---------------------------------------------------------------------------

  # Safety net: whenever a membership row is destroyed by *any* code path —
  # {.cleanup_for_asset!}, a cascading `dependent: :destroy` from `Asset#destroy`
  # (e.g. `Folder#destroy`), or anything else — make sure the parent group
  # never keeps showing as "pending" with fewer than 2 members. Without this
  # callback, a caller that hard-destroys an asset without going through
  # {.cleanup_for_asset!} would silently leave a stale single-member group
  # visible in the Duplicate Manager (see AGENTS.md bug report).
  after_destroy :auto_resolve_group_if_depleted

  # ---------------------------------------------------------------------------
  # Cleanup
  # ---------------------------------------------------------------------------

  # Removes +asset+ from every {DuplicateGroup} it belongs to and
  # auto-resolves any group left with fewer than 2 members.
  #
  # Must be called before hard-destroying an {Asset} — the
  # +fk_rails_e5995b56ce+ foreign key on this table otherwise raises
  # +ActiveRecord::InvalidForeignKey+ (PG::ForeignKeyViolation) whenever the
  # asset participated in duplicate detection.
  #
  # @param asset [Asset] the asset being permanently deleted
  # @param log_prefix [String] tag prepended to log lines (helps distinguish
  #   callers, e.g. "[BinPurge]" vs "[AssetsController]")
  # @return [void]
  def self.cleanup_for_asset!(asset, log_prefix: "[DuplicateGroupAsset]")
    where(asset_id: asset.id).find_each do |dga|
      dga.destroy!
      # Resolution now happens in the `after_destroy` callback below, but we
      # keep this rescue here since callers historically relied on cleanup
      # being non-fatal for the asset-deletion flow it's embedded in.
    rescue StandardError => e
      # Non-fatal: log and continue with the asset deletion
      Rails.logger.warn("#{log_prefix} Could not clean up duplicate group for asset ##{asset.id}: #{e.message}")
    end
  end

  private

  # @return [void]
  def auto_resolve_group_if_depleted
    group = duplicate_group
    return unless group
    return unless group.status == "pending"

    remaining = group.duplicate_group_assets.count
    return if remaining >= 2

    group.update!(status: "resolved", total_count: remaining)
    Rails.logger.info("[DuplicateGroupAsset] Auto-resolved DuplicateGroup ##{group.id} (only #{remaining} member(s) left)")
  rescue StandardError => e
    Rails.logger.warn("[DuplicateGroupAsset] Could not auto-resolve DuplicateGroup ##{group&.id}: #{e.message}")
  end
end
