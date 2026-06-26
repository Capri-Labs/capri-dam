# Service object responsible for detecting duplicate assets by SHA-256
# checksum and maintaining the +duplicate_groups+ / +duplicate_group_assets+
# tables.
#
# == Detection algorithm
#
# 1. Check whether duplicate detection is enabled (Setting key
#    +duplicate_manager_enabled+).  Returns immediately when disabled.
#
# 2. Look up all {AssetVersion} records whose +properties->>'checksum_sha256'+
#    matches +checksum+, excluding the version that was just uploaded.
#
# 3. If no existing matches are found → no duplicate, return +nil+.
#
# 4. If matches are found:
#    a. Find or create a {DuplicateGroup} for this checksum.
#    b. Register all matched assets (including the newly-uploaded one) as
#       {DuplicateGroupAsset} members.
#    c. Mark the earliest asset as +is_original: true+.
#    d. Update +total_count+ on the group.
#    e. Fire an Inbox {Notification} to the uploading user if inbox
#       notifications are enabled.
#
# == Usage
#
#   result = DuplicateDetectionService.call(
#     asset:    @asset,
#     checksum: "abc123…",
#     user:     current_user,
#   )
#   result.duplicate_group  # => DuplicateGroup or nil
#   result.new_duplicates   # => Integer (number of previously-unknown duplicates found)
#
# @see DuplicateGroup
# @see DuplicateDetectionWorker
class DuplicateDetectionService
  # Lightweight value object returned from {.call}.
  Result = Struct.new(:duplicate_group, :new_duplicates, :enabled, keyword_init: true) do
    def duplicate_detected?
      duplicate_group.present?
    end
  end

  # ---------------------------------------------------------------------------
  # Entry point
  # ---------------------------------------------------------------------------

  # @param asset    [Asset]   the newly uploaded asset
  # @param checksum [String]  the SHA-256 hex digest of the uploaded file
  # @param user     [User]    the user who performed the upload
  # @return [Result]
  def self.call(asset:, checksum:, user:)
    new(asset: asset, checksum: checksum, user: user).call
  end

  # ---------------------------------------------------------------------------
  # Initializer
  # ---------------------------------------------------------------------------

  def initialize(asset:, checksum:, user:)
    @asset    = asset
    @checksum = checksum
    @user     = user
  end

  # ---------------------------------------------------------------------------
  # Main logic
  # ---------------------------------------------------------------------------

  def call
    unless detection_enabled?
      return Result.new(duplicate_group: nil, new_duplicates: 0, enabled: false)
    end

    # Find all asset versions that carry the same checksum, excluding the
    # version that belongs to the current asset.
    matching_versions = AssetVersion
      .includes(:asset)
      .where("properties->>'checksum_sha256' = ?", @checksum)
      .where.not(asset_id: @asset.id)
      .joins(:asset)
      .merge(Asset.where(deleted_at: nil)) # exclude soft-deleted

    if matching_versions.empty?
      return Result.new(duplicate_group: nil, new_duplicates: 0, enabled: true)
    end

    existing_asset_ids = matching_versions.map(&:asset_id).uniq
    new_duplicates     = 0

    group = ActiveRecord::Base.transaction do
      # Find or create the group for this checksum.
      # If a previous pending group exists, reopen it; otherwise create fresh.
      dup_group = DuplicateGroup.find_or_initialize_by(checksum: @checksum, status: "pending")
      dup_group.save! if dup_group.new_record?

      # Register the newly uploaded asset.
      register_member(dup_group, @asset.id)

      # Register all existing matching assets.
      existing_asset_ids.each do |aid|
        added = register_member(dup_group, aid)
        new_duplicates += 1 if added
      end

      # Mark the original (oldest created_at).
      mark_original(dup_group)

      # Keep total_count in sync.
      dup_group.update!(total_count: dup_group.duplicate_group_assets.count)
      dup_group
    end

    send_inbox_notification(group) if inbox_notifications_enabled?

    Result.new(duplicate_group: group, new_duplicates: new_duplicates, enabled: true)
  rescue StandardError => e
    Rails.logger.error(
      "[DuplicateDetectionService] Error for asset #{@asset&.id}: #{e.class}: #{e.message}"
    )
    Result.new(duplicate_group: nil, new_duplicates: 0, enabled: true)
  end

  private

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # @return [Boolean]
  def detection_enabled?
    val = Setting.get("duplicate_manager_enabled")
    # Stored as a Boolean or the string "true" depending on serialiser version.
    val == true || val == "true"
  end

  # @return [Boolean]
  def inbox_notifications_enabled?
    val = Setting.get("duplicate_manager_inbox_notifications")
    val.nil? || val == true || val == "true"   # default: enabled
  end

  # Adds +asset_id+ to the group if not already present.
  #
  # @param group    [DuplicateGroup]
  # @param asset_id [String]  UUID
  # @return [Boolean] +true+ if a new member was added
  def register_member(group, asset_id)
    return false if DuplicateGroupAsset.exists?(
      duplicate_group_id: group.id,
      asset_id:           asset_id
    )

    DuplicateGroupAsset.create!(
      duplicate_group_id: group.id,
      asset_id:           asset_id,
      is_original:        false,
    )
    true
  rescue ActiveRecord::RecordNotUnique
    false
  end

  # Sets +is_original: true+ on the earliest-created member.
  #
  # @param group [DuplicateGroup]
  # @return [void]
  def mark_original(group)
    oldest_asset = Asset
      .where(id: group.duplicate_group_assets.select(:asset_id))
      .order(:created_at)
      .first

    return unless oldest_asset

    # Clear any previous is_original flags first.
    group.duplicate_group_assets.update_all(is_original: false)
    group.duplicate_group_assets
         .where(asset_id: oldest_asset.id)
         .update_all(is_original: true)
  end

  # Creates an Inbox {Notification} for the uploading user.
  #
  # One notification per upload event (not per group) to avoid flooding
  # the Inbox when many duplicates are uploaded at once.
  #
  # @param group [DuplicateGroup]
  # @return [void]
  def send_inbox_notification(group)
    return unless @user

    Notification.create!(
      user:       @user,
      title:      "Duplicate Assets Detected",
      message:    "#{group.total_count} asset(s) share the same file content. Review them in the Duplicate Manager.",
      action_url: "/duplicates",
    )
  rescue StandardError => e
    Rails.logger.warn(
      "[DuplicateDetectionService] Notification failed for user #{@user&.id}: #{e.message}"
    )
  end
end
