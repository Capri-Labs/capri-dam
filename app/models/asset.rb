# Core digital-asset domain model for the Headless DAM platform.
#
# An +Asset+ represents a single media item (image, video, document, …) owned
# by a {User} and optionally placed inside a {Folder}.  The binary file is
# **never** stored directly on the asset row; instead each upload or edit
# creates an immutable {AssetVersion} snapshot.  The currently active version
# is tracked via the +active_version_id+ foreign key so that version history
# is always preserved.
#
# == Status lifecycle
#
#   draft → pending → processing → ready
#                               ↓
#                          in_review → approved / rejected
#                               ↓
#                             failed (terminal, retryable by support)
#
# == AI / Vector search
#
# After every save that touches +properties+, the model publishes an
# +asset.needs_embedding+ event over Redis so that an external AI gateway can
# generate and store a semantic vector in the associated {AssetEmbedding}.
# The {.nearest_to_vector} scope then enables cosine-similarity search using
# the +neighbor+ gem.
#
# == Soft deletion
#
# Assets are never hard-deleted by end users.  {SoftDeletable} provides the
# +deleted_at+ semantics; permanently removing an asset (with all physical
# files) is an explicit admin operation in {Api::V1::AssetsController#permanent_delete}.
#
# @see AssetVersion
# @see AssetEmbedding
# @see SoftDeletable
class Asset < ApplicationRecord
  include SoftDeletable

  # ---------------------------------------------------------------------------
  # Associations
  # ---------------------------------------------------------------------------

  # @!attribute [r] user
  #   @return [User] the owner who uploaded the asset
  belongs_to :user

  # @!attribute [r] folder
  #   @return [Folder, nil] the folder this asset lives in; +nil+ means root
  belongs_to :folder, optional: true

  # @!attribute [r] asset_versions
  #   @return [ActiveRecord::Associations::CollectionProxy<AssetVersion>]
  #     all immutable snapshots of this asset, ordered by creation time
  has_many :asset_versions, dependent: :destroy

  # @!attribute [r] active_version
  #   @return [AssetVersion, nil] the version currently presented to consumers
  belongs_to :active_version, class_name: "AssetVersion", optional: true

  has_many :workflow_instances, dependent: :destroy

  # ActiveStorage attachment on the asset itself (legacy; new uploads use AssetVersion#file).
  has_one_attached :file

  # @!attribute [r] asset_embedding
  #   @return [AssetEmbedding, nil] the AI vector for semantic similarity search
  has_one :asset_embedding, dependent: :destroy

  has_many :collection_assets, dependent: :destroy

  # @!attribute [r] collections
  #   @return [ActiveRecord::Associations::CollectionProxy<Collection>]
  has_many :collections, through: :collection_assets

  # ---------------------------------------------------------------------------
  # Validations
  # ---------------------------------------------------------------------------

  validates :title, presence: true

  # ---------------------------------------------------------------------------
  # Enums
  # ---------------------------------------------------------------------------

  # @!attribute [rw] status
  #   @return [String] current processing / approval state of the asset
  enum :status, {
    draft:      0,
    pending:    1,
    processing: 2,
    ready:      3,
    in_review:  4,
    approved:   5,
    rejected:   6,
    failed:     7,
  }, default: :draft

  # ---------------------------------------------------------------------------
  # Scopes
  # ---------------------------------------------------------------------------

  # Active (non-deleted) assets that have been fully processed and published.
  # @return [ActiveRecord::Relation]
  scope :published, -> { where(status: :active) }

  # Nearest-neighbour cosine search using the +neighbor+ gem and pgvector.
  #
  # @param vector [Array<Float>] the query embedding (must match stored dimensions)
  # @return [ActiveRecord::Relation] assets ordered by cosine similarity, closest first
  scope :nearest_to_vector, ->(vector) {
    return none if vector.blank?

    joins(:asset_embedding)
      .merge(AssetEmbedding.nearest_neighbors(:embedding, vector, distance: "cosine"))
      .select("assets.*")
  }

  # ---------------------------------------------------------------------------
  # Callbacks
  # ---------------------------------------------------------------------------

  # Publishes an embedding-request event to Redis after every create/update.
  after_commit :broadcast_for_embedding, on: [ :create, :update ]

  after_initialize :set_property_defaults, if: :new_record?

  # ---------------------------------------------------------------------------
  # Public instance methods
  # ---------------------------------------------------------------------------

  # Returns the ActiveStorage file attachment on the currently active version.
  #
  # @return [ActiveStorage::Attached::One, nil]
  def current_file
    active_version&.file
  end

  # Returns the version number that should be assigned to the next new version.
  #
  # @return [Integer] max existing version number + 1, or 1 if no versions exist
  def next_version_number
    (asset_versions.maximum(:version_number) || 0) + 1
  end

  private

  # Enqueues smart-collection routing after an asset is created or updated.
  # @api private
  def trigger_smart_routing
    SmartCollectionRouterWorker.perform_async(self.id)
  end

  # Publishes an +asset.needs_embedding+ event over the Redis pub/sub channel
  # so the AI gateway can generate and persist a new semantic vector.
  #
  # Failures are intentionally swallowed — a downed Redis must never roll back
  # or crash a metadata save.
  # @api private
  def broadcast_for_embedding
    return if properties.blank?

    payload = { event: "asset.needs_embedding", asset_uuid: self.id }.to_json
    redis   = Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"))
    redis.publish("ai_gateway_events", payload)
  rescue StandardError => e
    Rails.logger.warn("[Asset##{id}] embedding broadcast skipped: #{e.message}")
  end

  # Seeds the +properties+ JSONB column with safe default values on build.
  # @api private
  def set_property_defaults
    self.properties ||= {
      description:  "",
      usage_terms:  "Internal Use Only",
      alt_text:     "",
      tags:         [],
    }
  end
end
