class Api::V1::DataHealthController < ApplicationController
  before_action :authenticate_hybrid!
  before_action :require_admin!

  def metrics
    # In a production environment, these queries should be cached
    # via Redis (e.g., Rails.cache.fetch) and updated nightly to prevent DB strain.

    total_active_bytes = Asset.sum(:file_size)
    orphaned_bytes = Asset.left_outer_joins(:collection_assets).where(collection_assets: { id: nil }).sum(:file_size)

    # Pulled directly from our IngestionItem tracking
    prevented_duplicate_bytes = IngestionItem.flagged_duplicate.sum(:file_size)

    render json: {
      storage: {
        total_allocated_tb: 20.0, # This would come from your AWS Account quota API
        active_used_tb: bytes_to_tb(total_active_bytes),
        orphaned_wasted_tb: bytes_to_tb(orphaned_bytes),
        duplicates_prevented_tb: bytes_to_tb(prevented_duplicate_bytes),
      },
      debt_flags: generate_debt_flags,
    }, status: :ok
  end

  private

  def bytes_to_tb(bytes)
    (bytes.to_f / (1024**4)).round(2)
  end

  def generate_debt_flags
    [
      {
        id: "d1",
        type: "orphaned",
        title: "Orphaned Legacy Assets",
        count: Asset.left_outer_joins(:collection_assets).where(collection_assets: { id: nil }).count,
        impact: "High",
      },
      {
        id: "d2",
        type: "copyright",
        title: "Missing Usage Rights / Expiry",
        # Assuming JSONB query for assets without copyright properties
        count: Asset.where("properties->>'copyright' IS NULL").count,
        impact: "Critical",
      },
      {
        id: "d3",
        type: "stale",
        title: "Stale Media (Unaccessed > 3 Yrs)",
        count: Asset.where("last_accessed_at < ?", 3.years.ago).count,
        impact: "Medium",
      },
    ]
  end
end
