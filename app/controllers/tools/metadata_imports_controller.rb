module Tools
  class MetadataImportsController < ApplicationController
    before_action :authenticate_hybrid!

    def index
      @active_view = "MetadataImport"
    end
  end
end
