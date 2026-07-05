module Tools
  class MetadataExportsController < ApplicationController
    before_action :authenticate_hybrid!

    def index
      @active_view = "MetadataExport"
    end
  end
end
