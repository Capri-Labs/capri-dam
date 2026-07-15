# Renders the custom 404 screen for requests that don't match any defined
# route (see the catch-all route at the bottom of config/routes.rb). This is
# distinct from {ApplicationController#render_not_found}, which handles
# ActiveRecord::RecordNotFound raised *inside* a matched controller action —
# unmatched routes never reach a controller action at all, so they need
# their own catch-all route + controller.
class ErrorsController < ApplicationController
  def not_found
    render_not_found
  end
end
