module Admin
  class StorageBackendsController < BaseController
    def index
      render json: {
        storage_backends: StorageBackend.order(:name).map { |backend| serialize_backend(backend) },
      }
    end

    def edit
      @backend = StorageBackend.find(params[:id])

      respond_to do |format|
        format.json { render json: { storage_backend: serialize_backend(@backend, include_configuration: true) } }
      end
    end

    def update
      @backend = StorageBackend.find(params[:id])

      if @backend.update(backend_params)
        # Ensure only one is active at a time
        StorageBackend.where.not(id: @backend.id).update_all(active: false) if @backend.active

        respond_to do |format|
          format.html { redirect_to admin_dashboard_path, notice: "Storage updated." }
          format.json do
            render json: {
              success: true,
              message: "Storage updated.",
              storage_backend: serialize_backend(@backend, include_configuration: true),
            }
          end
        end
      else
        respond_to do |format|
          format.html { render :edit, status: :unprocessable_entity }
          format.json { render json: { success: false, errors: @backend.errors.full_messages }, status: :unprocessable_entity }
        end
      end
    end

    private

    def serialize_backend(backend, include_configuration: false)
      payload = {
        id: backend.id,
        name: backend.name,
        provider_type: backend.provider_type,
        active: backend.active,
      }
      payload[:configuration] = backend.masked_configuration if include_configuration
      payload
    end

    def backend_params
      params.require(:storage_backend).permit(:name, :provider_type, :active)
    end
  end
end
