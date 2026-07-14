# Admin controller for the standalone "Security Policies" screen.
#
# This is a thin HTML shell only — it renders the React island
# (`SecurityPoliciesManager.jsx`) that lets an admin pick any user group and
# view/edit its full folder-permission matrix (`AclMatrix.jsx`) in one place,
# without first having to open that group's overlay from User Groups.
#
# All data (group list, folder policies) is fetched by the frontend from the
# existing `/admin/user_groups.json` and `/admin/folders/:folder_id/folder_policies`
# endpoints — no new JSON API is introduced by this screen.
module Admin
  class PoliciesController < Admin::BaseController
    def index
      @active_view = "Security Policies"
    end
  end
end
