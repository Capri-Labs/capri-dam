# app/controllers/admin/base_controller.rb
module Admin
  class BaseController < ApplicationController
    before_action :authenticate_user!
    before_action :ensure_admin!

    private

    def ensure_admin!
      # This uses the admin column we added to the User model earlier
      unless current_user.respond_to?(:admin?) && current_user.admin?
        redirect_to authenticated_root_path, alert: "Access Denied: Admins only."
      end
    end
  end
end
