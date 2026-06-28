module Api
  module V1
    class UploadRestrictionsController < ApplicationController
      before_action :authenticate_hybrid!
      before_action :require_admin!,       only: %i[update]
      before_action :require_admin_scope!, only: %i[update]

      # GET /api/v1/upload_restrictions
      def show
        allowed = Setting.get("upload_mime_restrictions")
        render json: { allowed_mime_types: Array(allowed) }
      end

      # PUT /api/v1/upload_restrictions
      def update
        mime_types = Array(params[:allowed_mime_types]).map(&:strip).reject(&:blank?).uniq
        Setting.set("upload_mime_restrictions", mime_types)
        render json: { allowed_mime_types: mime_types, message: "Upload restrictions saved successfully." }
      rescue StandardError => e
        render json: { error: e.message }, status: :unprocessable_entity
      end
    end
  end
end
