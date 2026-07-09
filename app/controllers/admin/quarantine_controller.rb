module Admin
  class QuarantineController < Admin::BaseController
    def index
      @active_view = "Quarantine Review"
    end
  end
end
