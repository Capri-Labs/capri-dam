# Service object responsible for detecting duplicate assets and maintaining
# the +duplicate_groups+ / +duplicate_group_assets+ tables.
#
# == Detection algorithm
#
# Two independent strategies are tried, in order — the first one that finds a
# match wins (an asset is never double-grouped by both strategies):
#
# 1. **Exact match** — {AssetVersion} records whose
#    +properties->>'checksum_sha256'+ is byte-for-byte identical to the
#    newly-uploaded file's checksum. This catches true duplicate uploads
#    (same file, same bytes).
#
# 2. **Perceptual match** — {AssetVersion} records whose +perceptual_hash+
#    (a 64-bit dHash computed by {AssetProcessorWorker#extract_perceptual_hash}
#    for every image) is within {PERCEPTUAL_HAMMING_THRESHOLD} bits of the
#    newly-uploaded image's hash. This catches the same photo saved in a
#    *different format or compression level* (e.g. the same picture exported
#    as both +.png+ and +.jpg+), where the SHA-256 checksums will always
#    differ even though the visual content is identical — something a plain
#    checksum comparison can never detect.
#
# Whichever strategy matches:
#   a. Find or create a {DuplicateGroup} for the checksum/hash key.
#   b. Register all matched assets (including the newly-uploaded one) as
#      {DuplicateGroupAsset} members.
#   c. Mark the earliest asset as +is_original: true+.
#   d. Update +total_count+ on the group.
#   e. Fire an Inbox {Notification} to the uploading user if inbox
#      notifications are enabled.
#
# Detection only runs when the Setting key +duplicate_manager_enabled+ is
# truthy.
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
# @see AssetProcessorWorker#extract_perceptual_hash
class DuplicateDetectionService
  # Maximum Hamming distance (out of 64 bits) between two perceptual hashes
  # for them to be considered the same underlying image. Empirically, the
  # same photo re-encoded to a different format/quality typically differs by
  # 0-10 bits, while visually distinct images differ by ~32 bits (50%).
  PERCEPTUAL_HAMMING_THRESHOLD = 10

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

    # 1. Exact match: same SHA-256 checksum (byte-identical files).
    result = detect_exact_duplicates
    return result if result

    # 2. Perceptual match: same visual content saved in a different format or
    #    at a different quality/compression level (e.g. .png vs .jpg), where
    #    the SHA-256 checksums will always differ even though a human would
    #    consider the files duplicates. See {#extract_perceptual_hash} in
    #    {AssetProcessorWorker} for how the hash is computed.
    result = detect_perceptual_duplicates
    return result if result

    Result.new(duplicate_group: nil, new_duplicates: 0, enabled: true)
  rescue StandardError => e
    Rails.logger.error(
      "[DuplicateDetectionService] Error for asset #{@asset&.id}: #{e.class}: #{e.message}"
    )
    Result.new(duplicate_group: nil, new_duplicates: 0, enabled: true)
  end

  private

  # ---------------------------------------------------------------------------
  # Detection strategies
  # ---------------------------------------------------------------------------

  # Groups assets whose {AssetVersion#properties}' +checksum_sha256+ is
  # byte-for-byte identical to the newly-uploaded asset's.
  #
  # @return [Result, nil] +nil+ when no exact match was found (so the caller
  #   can fall through to perceptual matching)
  def detect_exact_duplicates
    matching_versions = AssetVersion
      .includes(:asset)
      .where("asset_versions.properties->>'checksum_sha256' = ?", @checksum)
      .where.not(asset_id: @asset.id)
      .joins(:asset)
      .merge(Asset.where(deleted_at: nil)) # exclude soft-deleted

    return nil if matching_versions.empty?

    existing_asset_ids = matching_versions.map(&:asset_id).uniq
    build_group(checksum: @checksum, existing_asset_ids: existing_asset_ids)
  end

  # Groups assets whose perceptual hash is within {PERCEPTUAL_HAMMING_THRESHOLD}
  # bits of the newly-uploaded asset's — i.e. visually near-identical images
  # that were saved in a different format/encoding and therefore have
  # different SHA-256 checksums.
  #
  # @return [Result, nil] +nil+ when perceptual hashing isn't applicable
  #   (non-image asset, hash missing) or no near-duplicate was found
  def detect_perceptual_duplicates
    own_hash = perceptual_hash_for(@asset)
    return nil if own_hash.blank?

    candidates = AssetVersion
      .includes(:asset)
      .where("asset_versions.properties->>'perceptual_hash' IS NOT NULL")
      .where.not(asset_id: @asset.id)
      .joins(:asset)
      .merge(Asset.where(deleted_at: nil))

    matching_asset_ids = candidates.select do |version|
      candidate_hash = version.properties["perceptual_hash"]
      candidate_hash.present? &&
        hamming_distance(own_hash, candidate_hash) <= PERCEPTUAL_HAMMING_THRESHOLD
    end.map(&:asset_id).uniq

    return nil if matching_asset_ids.empty?

    # Use the perceptual hash as the group's checksum key (prefixed so it's
    # never mistaken for — or collide with — a real SHA-256 exact-match group).
    build_group(checksum: "phash:#{own_hash}", existing_asset_ids: matching_asset_ids)
  end

  # Hamming distance (number of differing bits) between two hex-encoded
  # perceptual hashes.
  #
  # @param hash_a [String] hex string
  # @param hash_b [String] hex string
  # @return [Integer]
  def hamming_distance(hash_a, hash_b)
    (hash_a.to_i(16) ^ hash_b.to_i(16)).to_s(2).count("1")
  end

  # @param asset [Asset]
  # @return [String, nil]
  def perceptual_hash_for(asset)
    asset.active_version&.properties&.dig("perceptual_hash") ||
      asset.properties["perceptual_hash"]
  end

  # Shared find-or-create-group + member-registration logic used by both
  # detection strategies.
  #
  # @param checksum           [String] the group's checksum/key column value
  # @param existing_asset_ids [Array<String>] UUIDs of assets already matched
  # @return [Result]
  def build_group(checksum:, existing_asset_ids:)
    new_duplicates = 0

    group = ActiveRecord::Base.transaction do
      dup_group = find_or_create_group(checksum)

      # Take a row-level lock on the group *before* touching its members.
      #
      # Without this, two uploads that both match the same group (e.g. the
      # same file uploaded twice in quick succession by different users) can
      # deadlock: worker A inserts (group, asset_x) then tries to insert
      # (group, asset_y), while worker B — running the same method for
      # asset_y — concurrently inserts (group, asset_y) then tries to insert
      # (group, asset_x). Each transaction ends up waiting on a row the other
      # already holds via +idx_dup_group_assets_unique+, a classic deadlock.
      #
      # Locking the parent +duplicate_groups+ row first serializes all
      # member-registration work for a given group across concurrent
      # transactions — the second worker simply blocks here until the first
      # commits, instead of racing it at the member-table level.
      dup_group.lock!

      register_member(dup_group, @asset.id)

      existing_asset_ids.each do |aid|
        added = register_member(dup_group, aid)
        new_duplicates += 1 if added
      end

      mark_original(dup_group)
      dup_group.update!(total_count: dup_group.duplicate_group_assets.count)
      dup_group
    end

    send_inbox_notification(group) if inbox_notifications_enabled?

    Result.new(duplicate_group: group, new_duplicates: new_duplicates, enabled: true)
  end

  # Finds the pending group for +checksum+, creating it if necessary.
  #
  # Uses find-then-create rather than +find_or_create_by!+ so that the
  # (rare) race where two transactions try to create the same group
  # simultaneously is handled explicitly: the loser's unique-index violation
  # is rescued and resolved by re-fetching the winner's row, rather than
  # bubbling up as an unhandled error.
  #
  # @param checksum [String]
  # @return [DuplicateGroup]
  def find_or_create_group(checksum)
    DuplicateGroup.find_by(checksum: checksum, status: "pending") ||
      DuplicateGroup.create!(checksum: checksum, status: "pending")
  rescue ActiveRecord::RecordNotUnique
    DuplicateGroup.find_by!(checksum: checksum, status: "pending")
  end

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
