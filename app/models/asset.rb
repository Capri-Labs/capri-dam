class Asset < ApplicationRecord
  belongs_to :user
  belongs_to :folder, optional: true

  # REMOVED: after_commit :trigger_upload_workflows, on: :create
  has_many :asset_versions, dependent: :destroy
  # The pointer to the currently active version
  belongs_to :active_version, class_name: 'AssetVersion', optional: true

  has_many :workflow_instances, dependent: :destroy
  has_one_attached :file

  # New AI Vector Association
  has_one :asset_embedding, dependent: :destroy

  # Trigger the asynchronous embedding generation whenever metadata changes
  after_commit :broadcast_for_embedding, on: [:create, :update]

  has_many :collection_assets, dependent: :destroy
  has_many :collections, through: :collection_assets

  validates :title, presence: true

  enum :status, {
    draft: 0,
    pending: 1,
    processing: 2,
    ready: 3,
    in_review: 4,
    approved: 5,
    rejected: 6,
    failed: 7
  }, default: :draft

  scope :published, -> { where(status: :active) }

  scope :nearest_to_vector, ->(vector) {
    return none if vector.blank?

    joins(:asset_embedding)
      .merge(AssetEmbedding.nearest_neighbors(:embedding, vector, distance: "cosine"))
      .select("assets.*")
  }

  after_initialize :set_property_defaults, if: :new_record?

  include SoftDeletable

  # Helper method to easily access the active file
  def current_file
    active_version&.file
  end

  # Helper method to get the latest version number
  def next_version_number
    (asset_versions.maximum(:version_number) || 0) + 1
  end

  private

  def trigger_smart_routing
    SmartCollectionRouterWorker.perform_async(self.id)
  end

  def broadcast_for_embedding
    return if properties.blank?

    payload = {
      event: 'asset.needs_embedding',
      asset_uuid: self.id
    }.to_json

    # 🚀 FIX: Initialize connection locally or use a central initializer
    # You should have a config/initializers/redis.rb, but this will stop the crash:
    redis = Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"))
    redis.publish('ai_gateway_events', payload)
  end

  def set_property_defaults
    self.properties ||= {
      description: "",
      usage_terms: "Internal Use Only",
      alt_text: "",
      tags: []
    }
  end
end