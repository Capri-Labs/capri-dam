class MetadataImportWorker
  include Sidekiq::Worker

  # CSV parsing + bulk metadata writes belong on a background queue so the
  # import never impedes user-facing requests.
  sidekiq_options queue: "metadata", retry: 3

  def perform(import_id)
    import = MetadataImport.find_by(id: import_id)
    return unless import
    return if import.completed? # idempotent guard

    import.update!(status: :processing)

    result = MetadataImportService::CsvProcessor.new(import).process

    # Attach the results CSV (source rows + status/message columns).
    import.result_file.purge if import.result_file.attached?
    import.result_file.attach(
      io:           StringIO.new(result.csv_string),
      filename:     results_filename(import),
      content_type: "text/csv"
    )

    import.update!(
      status:        :completed,
      total_rows:    result.total,
      success_count: result.success,
      failure_count: result.failure,
      expires_at:    Time.current + MetadataImport::RETENTION_PERIOD,
      error_message: nil
    )

    notify_user(import, success: true)
  rescue StandardError => e
    Rails.logger.error "💥 MetadataImportWorker failed for ##{import_id}: #{e.message}"
    import&.update(status: :failed, error_message: e.message)
    notify_user(import, success: false) if import
    raise e
  end

  private

  def results_filename(import)
    base = import.name.to_s.gsub(/\.csv\z/i, "").gsub(/[^\w\-]+/, "_")
    base = "metadata_import" if base.blank?
    "#{base}_results.csv"
  end

  def notify_user(import, success:)
    return unless import.user

    if success
      Notification.create!(
        user:       import.user,
        title:      "Metadata import complete",
        message:    "“#{import.name}” finished — #{import.success_count} succeeded, #{import.failure_count} failed of #{import.total_rows} row(s).",
        action_url: "/tools/metadata_imports"
      )
    else
      Notification.create!(
        user:       import.user,
        title:      "Metadata import failed",
        message:    "“#{import.name}” could not be processed. #{import.error_message}".strip,
        action_url: "/tools/metadata_imports"
      )
    end
  rescue StandardError => e
    Rails.logger.error "⚠️ Failed to notify user for import ##{import.id}: #{e.message}"
  end
end

