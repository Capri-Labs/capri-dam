module Tools
  class MetadataSchemasController < ApplicationController
    before_action :authenticate_hybrid!

    def index
      @active_view = "MetadataSchemas"
    end
  end
end
