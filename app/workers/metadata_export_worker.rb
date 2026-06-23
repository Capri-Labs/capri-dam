class MetadataExportWorker
  include Sidekiq::Worker

  # Heavy CSV generation belongs on the low-priority reports queue so it never
  # blocks user-facing emails or ingestion.
  sidekiq_options queue: "reports", retry: 3

  def perform(export_id)
    export = MetadataExport.find_by(id: export_id)
    return unless export
    return if export.completed? # idempotent guard against re-runs

    export.update!(status: :processing)

    files, total = MetadataExportService::CsvGenerator.new(export).generate

    # Replace any previous artifacts before re-attaching.
    export.files.purge if export.files.attached?

    files.each do |file|
      export.files.attach(
        io:           StringIO.new(file.data),
        filename:     file.filename,
        content_type: file.content_type
      )
    end

    export.update!(
      status:       :completed,
      total_assets: total,
      file_count:   files.size,
      expires_at:   Time.current + MetadataExport::RETENTION_PERIOD,
      error_message: nil
    )

    notify_user(export, success: true)
  rescue StandardError => e
    Rails.logger.error "💥 MetadataExportWorker failed for ##{export_id}: #{e.message}"
    export&.update(status: :failed, error_message: e.message)
    notify_user(export, success: false) if export
    raise e
  end

  private

  def notify_user(export, success:)
    return unless export.user

    if success
      Notification.create!(
        user:       export.user,
        title:      "Metadata export ready",
        message:    "“#{export.name}” finished — #{export.total_assets} asset(s) across #{export.file_count} file(s).",
        action_url: "/tools/metadata_exports"
      )
    else
      Notification.create!(
        user:       export.user,
        title:      "Metadata export failed",
        message:    "“#{export.name}” could not be generated. #{export.error_message}".strip,
        action_url: "/tools/metadata_exports"
      )
    end
  rescue StandardError => e
    Rails.logger.error "⚠️ Failed to notify user for export ##{export.id}: #{e.message}"
  end
end

