class DashboardController < ApplicationController
  # This ensures ONLY logged-in users can reach these actions
  before_action :authenticate_user!

  def index
    assets_scope = Asset.all

    if params[:search].present?
      @search_term = params[:search]
      # Using 'title' instead of 'name'
      #assets_scope = assets_scope.where("title ILIKE ?", "%#{@search_term}%")
      assets_scope = assets_scope.where(
        "title ILIKE :q OR properties->>'original_filename' ILIKE :q",
        q: "%#{@search_term}%"
      )
    end

    @assets_json = assets_scope.limit(20).map do |asset|
      {
        id: asset.id,
        uuid: asset.uuid,
        name: asset.title || "Untitled Asset", # Map 'title' to the 'name' prop React expects
        type: asset.properties&.dig('mime_type') || 'Unknown', # Pulling from your properties JSON
        size: asset.properties&.dig('size_human') || '0 KB'
      }
    end.to_json

    @workflows_json = Workflow.all.map { |wf|
      {
        id: wf.id,
        name: wf.name,
        description: wf.description,
        status: wf.status, # 'active', 'inactive'
        trigger_type: wf.trigger_type,
        step_count: wf.workflow_steps.count,
        # Fetching the name of the user who last modified it
        last_modified_by: User.find_by(id: wf.updated_by_id)&.full_name || "Admin",
        updated_at: wf.updated_at.strftime("%b %d, %Y %H:%M")
      }
    }.to_json

    # Force an empty array string if nothing is found
    @assets_json = "[]" if @assets_json.blank?

    # This line is critical! It fetches the apps from Doorkeeper
    @system_apps = Doorkeeper::Application.where(owner_id: nil)

    # Optional: if you also want to show backends
    @backends = StorageBackend.all
  end
end