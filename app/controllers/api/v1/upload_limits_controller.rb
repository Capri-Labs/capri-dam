module Api
  module V1
    # Manages the admin-configurable maximum upload file size (Tools › Asset
    # Configurations › Upload Limits). Defaults to 2 GB, matching AEM's
    # documented default asset upload size limit, and is enforced both here
    # (for the UI to read/display) and in {Api::V1::AssetsController#create}
    # (for actual server-side enforcement).
    class UploadLimitsController < ApplicationController
      before_action :authenticate_hybrid!
      before_action :require_admin!,       only: %i[update]
      before_action :require_admin_scope!, only: %i[update]

      DEFAULT_MAX_UPLOAD_SIZE_BYTES = 2.gigabytes

      # GET /api/v1/upload_limits
      def show
        render json: { max_upload_size_bytes: current_max_upload_size_bytes }
      end

      # PUT /api/v1/upload_limits
      def update
        bytes = params[:max_upload_size_bytes].to_i

        if bytes <= 0
          render json: { error: "Maximum upload size must be a positive number of bytes." }, status: :unprocessable_entity
          return
        end

        Setting.set("max_upload_size_bytes", bytes)
        render json: { max_upload_size_bytes: bytes, message: "Upload size limit saved successfully." }
      rescue StandardError => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      private

      def current_max_upload_size_bytes
        configured = Setting.get("max_upload_size_bytes")
        configured.present? ? configured.to_i : DEFAULT_MAX_UPLOAD_SIZE_BYTES
      end
    end
  end
end
