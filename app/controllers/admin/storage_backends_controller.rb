module Admin
  class StorageBackendsController < BaseController
    def edit
      @backend = StorageBackend.find(params[:id])
    end

    def update
      @backend = StorageBackend.find(params[:id])
      if @backend.update(backend_params)
        # Ensure only one is active at a time
        StorageBackend.where.not(id: @backend.id).update_all(active: false) if @backend.active
        redirect_to admin_dashboard_path, notice: "Storage updated."
      else
        render :edit
      end
    end

    private

    def backend_params
      params.require(:storage_backend).permit(:name, :provider_type, :active)
    end
  end
end