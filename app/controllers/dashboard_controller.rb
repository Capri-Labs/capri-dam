class DashboardController < ApplicationController
  before_action :authenticate_user!

  def index
    @active_view = "Overview"
    # 1. Base scope: Only search active assets (ignore the recycle bin)
    assets_scope = Asset.active

    # 2. Apply search filter if present
    if params[:search].present?
      @search_term = params[:search]
      assets_scope = assets_scope.where(
        "title ILIKE :q OR properties->>'original_filename' ILIKE :q",
        q: "%#{@search_term}%"
      )
    end

    # 3. Format and encode to a JSON string ONCE
    @assets_json = assets_scope.limit(20).map do |asset|
      {
        id: asset.id,
        uuid: asset.uuid,
        name: asset.title || "Untitled Asset",
        type: asset.properties&.dig("mime_type") || "Unknown",
        size: asset.properties&.dig("size_human") || "0 KB",
      }
    end.to_json

    # Fallback for an empty result set
    @assets_json = "[]" if @assets_json == "null" || @assets_json.blank?
  end

  def bin
    @active_view = "Bin"
    # Renders app/views/dashboard/bin.html.erb
  end

  def folders
    @active_view = "All Assets"
    # Renders app/views/dashboard/folders.html.erb
  end

  # Serves the /assets?id=UUID deep-link.
  # The HTML shell is identical to /folders; the React component reads
  # `data-initial-target-asset-id` to open the AssetViewer automatically.
  def assets
    @active_view = "All Assets"
    @asset_id    = params[:id].presence
    # Renders app/views/dashboard/assets.html.erb
  end

  def duplicates
    @active_view = "Duplicate Manager"
  end

  def search
    @active_view = "Search"
    # This just tells Rails to render app/views/dashboard/search.html.erb
  end
end
