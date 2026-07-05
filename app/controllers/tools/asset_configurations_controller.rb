module Tools
  class AssetConfigurationsController < ApplicationController
    before_action :authenticate_hybrid!

    def index
      if current_user.admin?
        @active_view = "AssetConfigurations"
      else
        redirect_to authenticated_root_path, alert: "Access denied: Administrator privileges required to manage asset configurations."
      end
    end
  end
end
