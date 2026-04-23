class DashboardController < ApplicationController
  # This ensures ONLY logged-in users can reach these actions
  before_action :authenticate_user!

  def index
    # Rails will now render the view that mounts your React Dashboard
  end
end