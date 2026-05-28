class DashboardController < ApplicationController
  before_action :authenticate_user!

  def index
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
        type: asset.properties&.dig('mime_type') || 'Unknown',
        size: asset.properties&.dig('size_human') || '0 KB'
      }
    end.to_json

    # Fallback for an empty result set
    @assets_json = "[]" if @assets_json == "null" || @assets_json.blank?
  end

  def bin
    # Renders app/views/dashboard/bin.html.erb
  end

  def folders
    # Renders app/views/dashboard/folders.html.erb
  end
end