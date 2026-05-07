class DashboardController < ApplicationController
  # This ensures ONLY logged-in users can reach these actions
  before_action :authenticate_user!

  def index
    # This line is critical! It fetches the apps from Doorkeeper
    @system_apps = Doorkeeper::Application.where(owner_id: nil)

    # Optional: if you also want to show backends
    @backends = StorageBackend.all
  end
end