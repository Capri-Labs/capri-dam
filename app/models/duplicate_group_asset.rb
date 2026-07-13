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
      group = dga.duplicate_group
      dga.destroy!

      # A group with fewer than 2 remaining members is no longer a valid
      # duplicate — resolve it automatically.
      remaining = group.duplicate_group_assets.count
      if remaining < 2
        group.update!(status: :resolved)
        Rails.logger.info("#{log_prefix} Auto-resolved DuplicateGroup ##{group.id} (only #{remaining} member(s) left)")
      end
    rescue StandardError => e
      # Non-fatal: log and continue with the asset deletion
      Rails.logger.warn("#{log_prefix} Could not clean up duplicate group for asset ##{asset.id}: #{e.message}")
    end
  end
end
