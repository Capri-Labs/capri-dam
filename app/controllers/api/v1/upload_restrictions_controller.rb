module Api
  module V1
    class UploadRestrictionsController < ApplicationController
      before_action :authenticate_user!

      # GET /api/v1/upload_restrictions
      def show
        allowed = Setting.get("upload_mime_restrictions")
        render json: { allowed_mime_types: Array(allowed) }
      end

      # PUT /api/v1/upload_restrictions
      def update
        unless current_user.admin?
          render json: { error: "Administrator privileges required." }, status: :forbidden and return
        end

        mime_types = Array(params[:allowed_mime_types]).map(&:strip).reject(&:blank?).uniq
        Setting.set("upload_mime_restrictions", mime_types)
        render json: { allowed_mime_types: mime_types, message: "Upload restrictions saved successfully." }
      rescue => e
        render json: { error: e.message }, status: :unprocessable_entity
      end
    end
  end
end
