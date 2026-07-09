require "csv"

module Api
  module V1
    class MetadataImportsController < ApplicationController
      include Rails.application.routes.url_helpers

      before_action :authenticate_hybrid!
      before_action :require_write_scope!, only: [ :create, :preview, :destroy ]
      before_action :set_import, only: [ :show, :download, :destroy ]

      # GET /api/v1/metadata_imports
      def index
        imports = current_user.metadata_imports.not_expired.recent.limit(100)
        render json: imports.map { |import| serialize(import) }
      end

      # GET /api/v1/metadata_imports/:id
      def show
        render json: serialize(@import)
      end

      # GET /api/v1/metadata_imports/template
      # Downloads the fixed starter template so users begin with the right columns.
      def template
        csv = CSV.generate do |out|
          out << MetadataImport::TEMPLATE_COLUMNS
          out << [ "/Adventures/Cycling/bike.jpg", "Mountain Bike", "Trail ready", "WKND Site", "Internal Use Only", "Cyclist on a trail", "bike|outdoor|sport" ]
        end
        send_data csv,
                  filename: "metadata_import_template.csv",
                  type: "text/csv",
                  disposition: "attachment"
      end

      # POST /api/v1/metadata_imports/preview  (multipart/form-data)
      def preview
        return render_missing_file_error unless source_file.present?

        import = build_preview_import
        return render json: { errors: import.errors.full_messages }, status: :unprocessable_entity unless import.valid?

        result = MetadataImportService::CsvProcessor.new(
          import,
          dry_run: true,
          source_csv: source_file.read
        ).process

        render json: serialize_preview(import, result)
      rescue StandardError => e
        render json: { errors: [ e.message ] }, status: :unprocessable_entity
      end

      # POST /api/v1/metadata_imports  (multipart/form-data)
      def create
        return render_missing_file_error unless source_file.present?

        import = current_user.metadata_imports.new(import_params)
        import.name   = import.name.presence || source_file.original_filename.to_s
        import.status = :pending

        if import.save
          enqueue(import)
          render json: serialize(import), status: :accepted
        else
          render json: { errors: import.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # GET /api/v1/metadata_imports/:id/download?type=source|result
      def download
        attachment = params[:type].to_s == "result" ? @import.result_file : @import.source_file

        unless attachment.attached?
          return render json: { error: "File not available." }, status: :not_found
        end

        redirect_to rails_blob_path(attachment, disposition: "attachment"), allow_other_host: false
      end

      # DELETE /api/v1/metadata_imports/:id
      def destroy
        @import.source_file.purge if @import.source_file.attached?
        @import.result_file.purge if @import.result_file.attached?
        @import.destroy
        render json: { success: true }
      end

      private

      def set_import
        @import = current_user.metadata_imports.find(params[:id])
      end

      def source_file
        params.dig(:metadata_import, :source_file)
      end

      def import_params
        raw_ignored_columns = params.dig(:metadata_import, :ignored_columns)
        permitted = params.require(:metadata_import).permit(
          :name, :source_file, :batch_size, :field_separator, :multi_value_delimiter,
          :launch_workflows, :asset_path_column, :scheduled_at, ignored_columns: []
        )

        # FormData sends ignored_columns as a comma-joined string when not an array.
        if raw_ignored_columns.is_a?(String)
          permitted[:ignored_columns] = raw_ignored_columns.split(",").map(&:strip).reject(&:blank?)
        end
        permitted
      end

      def enqueue(import)
        if import.scheduled_at.present? && import.scheduled_at > Time.current
          MetadataImportWorker.perform_at(import.scheduled_at, import.id)
        else
          MetadataImportWorker.perform_async(import.id)
        end
      end

      def build_preview_import
        import = current_user.metadata_imports.new(import_params.except(:source_file))
        import.name = import.name.presence || source_file.original_filename.to_s
        import
      end

      def render_missing_file_error
        render json: { errors: [ "Please select a CSV file." ] }, status: :unprocessable_entity
      end

      def serialize(import)
        {
          id:                    import.id,
          name:                  import.name,
          status:                import.status,
          batch_size:            import.batch_size,
          field_separator:       import.field_separator,
          multi_value_delimiter: import.multi_value_delimiter,
          launch_workflows:      import.launch_workflows,
          asset_path_column:     import.asset_path_column,
          ignored_columns:       import.ignored_columns,
          total_rows:            import.total_rows,
          success_count:         import.success_count,
          failure_count:         import.failure_count,
          error_message:         import.error_message,
          created_by:            import.user&.name || import.user&.email,
          created_at:            import.created_at&.strftime("%b %d, %Y at %H:%M"),
          scheduled_at:          import.scheduled_at&.strftime("%b %d, %Y at %H:%M"),
          expires_at:            import.expires_at&.strftime("%b %d, %Y"),
          source_file:           file_meta(import, :source),
          result_file:           file_meta(import, :result),
        }
      end

      def serialize_preview(import, result)
        {
          dry_run:               true,
          name:                  import.name,
          batch_size:            import.batch_size,
          field_separator:       import.field_separator,
          multi_value_delimiter: import.multi_value_delimiter,
          launch_workflows:      false,
          asset_path_column:     import.asset_path_column,
          ignored_columns:       import.ignored_columns,
          total_rows:            result.total,
          success_count:         result.success,
          failure_count:         result.failure,
          preview_csv:           result.csv_string,
          rows:                  result.rows.map { |row| serialize_preview_row(row) },
        }
      end

      def serialize_preview_row(row)
        {
          row_number:          row.row_number,
          asset_path:          row.asset_path,
          resolved_asset_path: row.resolved_asset_path,
          status:              row.status,
          message:             row.message,
          changes:             row.changes,
        }
      end

      def file_meta(import, type)
        attachment = type == :result ? import.result_file : import.source_file
        return nil unless attachment.attached?

        {
          filename:     attachment.blob.filename.to_s,
          byte_size:    attachment.blob.byte_size,
          download_url: download_api_v1_metadata_import_path(import, type: type),
        }
      end
    end
  end
end
