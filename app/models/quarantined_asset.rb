class QuarantinedAsset < ApplicationRecord
  VALID_STATUSES = %w[pending_review resolved discarded].freeze

  belongs_to :system_connector
  belongs_to :asset, optional: true
  belongs_to :reviewed_by, class_name: "User", optional: true

  validates :status, presence: true, inclusion: { in: VALID_STATUSES }

  before_validation :set_default_status, on: :create

  scope :pending_review, -> { where(status: "pending_review") }
  scope :resolved, -> { where(status: "resolved") }
  scope :discarded, -> { where(status: "discarded") }

  def release!(reviewer:, notes: nil)
    ActiveRecord::Base.transaction do
      released_asset = asset || create_released_asset!

      released_asset.restore if released_asset.trashed?
      released_asset.update!(status: "ready") unless released_asset.ready?

      update!(
        asset: asset || released_asset,
        status: "resolved",
        reviewed_by: reviewer,
        reviewed_at: Time.current,
        review_notes: notes.presence
      )
    end
  end

  def discard!(reviewer:, notes: nil)
    ActiveRecord::Base.transaction do
      if asset.present?
        asset.update!(status: "rejected") unless asset.rejected?
        asset.soft_delete unless asset.trashed?
      end

      update!(
        status: "discarded",
        reviewed_by: reviewer,
        reviewed_at: Time.current,
        review_notes: notes.presence
      )
    end
  end

  def payload_data
    original_payload.is_a?(Hash) ? original_payload : {}
  end

  def payload_asset_data
    payload_data["asset"].is_a?(Hash) ? payload_data["asset"] : {}
  end

  def payload_title
    payload_asset_data["name"].presence ||
      payload_asset_data["title"].presence ||
      payload_data["filename"].presence ||
      "Untitled Quarantined Asset"
  end

  def payload_properties
    raw = payload_asset_data["properties"]
    raw.is_a?(Hash) ? raw.stringify_keys : {}
  end

  def payload_owner
    owner_id = payload_asset_data["user_id"] || payload_data["user_id"]
    User.find_by(id: owner_id) || User.first
  end

  def payload_uploaded_at
    raw_value = payload_asset_data["uploaded_at"] || payload_data["uploaded_at"]
    return if raw_value.blank?

    Time.zone.parse(raw_value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def payload_content_type
    payload_properties["content_type"].presence ||
      payload_properties["mime_type"].presence ||
      payload_asset_data["content_type"].presence ||
      payload_data["content_type"].presence
  end

  private

  def set_default_status
    self.status ||= "pending_review"
  end

  def create_released_asset!
    owner = payload_owner
    raise ActiveRecord::RecordNotFound, "No user available for released quarantined asset" unless owner

    Asset.create!(
      user: owner,
      title: payload_title,
      status: "ready",
      uuid: SecureRandom.uuid,
      properties: released_asset_properties
    )
  end

  def released_asset_properties
    payload_properties.merge("original_filename" => payload_title)
  end
end
