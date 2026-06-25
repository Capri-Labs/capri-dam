module Tools
  class AssetConfigurationsController < ApplicationController
    before_action :authenticate_hybrid!

    def index
      unless current_user.admin?
        redirect_to root_path, alert: "Access denied: Administrator privileges required to manage asset configurations."
      end
    end
  end
end
