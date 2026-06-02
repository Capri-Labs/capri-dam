class CollectionsController < ApplicationController
  # This serves the UI page at http://localhost:3000/collections

  def index
    # Tells the global layout to highlight this in the sidebar
    @active_view = 'Collections'

    # We do NOT render json here. We just let Rails render
    # the empty app/views/collections/index.html.erb file implicitly.
  end
end