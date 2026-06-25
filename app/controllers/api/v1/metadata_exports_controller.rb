module Api
  module V1
    class MetadataExportsController < ApplicationController
      include Rails.application.routes.url_helpers
      before_action :authenticate_user!
      before_action :set_export, only: [ :show, :download, :destroy ]

      # GET /api/v1/metadata_exports
      # Lists the current user's (non-expired) exports for the reuse table.
      def index
        exports = current_user.metadata_exports.not_expired.recent.limit(100)
        render json: exports.map { |e| serialize(e) }
      end

      # GET /api/v1/metadata_exports/:id
      def show
        render json: serialize(@export)
      end

      # GET /api/v1/metadata_exports/properties?folder_id=&include_subfolders=
      # Returns the available metadata property keys so the UI can offer a
      # "selective properties" picker.
      def properties
        folder_id = params[:folder_id].presence
        folder_id = nil if folder_id == "root"
        cascade   = ActiveModel::Type::Boolean.new.cast(params[:include_subfolders])

        keys = collect_property_keys(folder_id, cascade)
        render json: { properties: keys }
      end

      # POST /api/v1/metadata_exports
      def create
        export = current_user.metadata_exports.new(export_params)
        export.folder_id = nil if export.folder_id == "root"
        export.status    = :pending

        if export.save
          enqueue(export)
          render json: serialize(export), status: :accepted
        else
          render json: { errors: export.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # GET /api/v1/metadata_exports/:id/download?attachment_id=
      def download
        unless @export.completed? && @export.files.attached?
          return render json: { error: "Export not ready or files missing." }, status: :not_found
        end

        attachment =
          if params[:attachment_id].present?
            @export.files.attachments.find_by(id: params[:attachment_id])
          else
            @export.files.attachments.first
          end

        return render json: { error: "File not found." }, status: :not_found unless attachment

        redirect_to rails_blob_path(attachment.blob, disposition: "attachment"), allow_other_host: false
      end

      # DELETE /api/v1/metadata_exports/:id
      def destroy
        @export.files.purge if @export.files.attached?
        @export.destroy
        render json: { success: true }
      end

      private

      def set_export
        @export = current_user.metadata_exports.find(params[:id])
      end

      def export_params
        params.require(:metadata_export).permit(
          :name, :folder_id, :include_subfolders, :property_mode, :scheduled_at,
          selected_properties: []
        )
      end

      def enqueue(export)
        if export.scheduled_at.present? && export.scheduled_at > Time.current
          MetadataExportWorker.perform_at(export.scheduled_at, export.id)
        else
          MetadataExportWorker.perform_async(export.id)
        end
      end

      def serialize(export)
        {
          id:                 export.id,
          name:               export.name,
          status:             export.status,
          folder_id:          export.folder_id,
          folder_name:        export.folder&.name || "Root",
          include_subfolders: export.include_subfolders,
          property_mode:      export.property_mode,
          selected_properties: export.selected_properties,
          total_assets:       export.total_assets,
          file_count:         export.file_count,
          error_message:      export.error_message,
          created_by:         export.user&.name || export.user&.email,
          created_at:         export.created_at&.strftime("%b %d, %Y at %H:%M"),
          scheduled_at:       export.scheduled_at&.strftime("%b %d, %Y at %H:%M"),
          expires_at:         export.expires_at&.strftime("%b %d, %Y"),
          files:              serialize_files(export),
        }
      end

      def serialize_files(export)
        return [] unless export.files.attached?

        export.files.attachments.map do |att|
          {
            id:           att.id,
            filename:     att.blob.filename.to_s,
            byte_size:    att.blob.byte_size,
            download_url: download_api_v1_metadata_export_path(export, attachment_id: att.id),
          }
        end
      end

      def collect_property_keys(folder_id, cascade)
        folder_ids = resolve_folder_ids(folder_id, cascade)

        scope =
          if folder_id.blank?
            cascade ? Asset.active : Asset.active.where(folder_id: nil)
          else
            Asset.active.where(folder_id: folder_ids)
          end

        keys = []
        scope.pluck(:properties).each do |props|
          keys.concat(props.keys.map(&:to_s)) if props.is_a?(Hash)
        end
        keys.uniq.sort
      end

      def resolve_folder_ids(folder_id, cascade)
        return [] if folder_id.blank?

        ids = [ folder_id ]
        return ids unless cascade

        queue = [ folder_id ]
        until queue.empty?
          children = Folder.active.where(parent_id: queue).pluck(:id)
          new_ids  = children - ids
          ids.concat(new_ids)
          queue = new_ids
        end
        ids
      end
    end
  end
end
