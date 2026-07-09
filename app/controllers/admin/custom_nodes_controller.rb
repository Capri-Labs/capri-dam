module Admin
  class CustomNodesController < Admin::BaseController
    def index
      @active_view = "Custom Nodes"
    end
  end
end
