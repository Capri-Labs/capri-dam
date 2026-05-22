class DashboardController < ApplicationController
  # This ensures ONLY logged-in users can reach these actions
  before_action :authenticate_user!

  def index
    assets_scope = Asset.all

    if params[:search].present?
      @search_term = params[:search]
      assets_scope = assets_scope.where(
        "title ILIKE :q OR properties->>'original_filename' ILIKE :q",
        q: "%#{@search_term}%"
      )
    end

    @assets_json = assets_scope.limit(20).map do |asset|
      {
        id: asset.id,
        uuid: asset.uuid,
        name: asset.title || "Untitled Asset",
        type: asset.properties&.dig('mime_type') || 'Unknown',
        size: asset.properties&.dig('size_human') || '0 KB'
      }
    end.to_json

    # Force an empty array string if nothing is found
    @assets_json = "[]" if @assets_json.blank?

    # This line is critical! It fetches the apps from Doorkeeper
    @system_apps = Doorkeeper::Application.where(owner_id: nil)

    # Optional: if you also want to show backends
    @backends = StorageBackend.all
  end
end