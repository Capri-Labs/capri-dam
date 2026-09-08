class PortalsController < ApplicationController
  # This screen lists who has been sent what outside the organisation, so it is
  # gated even though the data itself is served separately by the API.
  before_action :authenticate_user!

  # Serves the UI page at /portals. The React app does the rest; everything it
  # needs comes from /api/v1/portals.
  def index
    @active_view = "Portals"
  end
end
