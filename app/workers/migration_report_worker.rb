# MigrationReportWorker
# ─────────────────────────────────────────────────────────────────────────────
# Generates a migration summary report and sends ONE batch-level email
# notification. Called automatically when MigrationCommitWorker finalizes.
# Never called per-asset — only once per batch completion.
#
# Queue: 'reports'  (lowest priority)
class MigrationReportWorker
  include Sidekiq::Worker
  sidekiq_options queue: "reports", retry: 1

  def perform(batch_id)
    batch = IngestionBatch.find_by(id: batch_id)
    return unless batch

    Rails.logger.info("[MigrationReport] Generating report for batch #{batch.id}...")

    # 1. Compute full statistics
    stats = compute_stats(batch)

    # 2. Generate and persist the report snapshot (CSV + human-readable summary)
    snapshot = persist_report_snapshot(batch, stats)

    # 3. Send ONE batch-level email to the initiator
    notify_batch_complete(batch, stats, snapshot)

    # 4. Update batch with report reference
    batch.update!(report_snapshot_id: snapshot&.id)

    Rails.logger.info("[MigrationReport] Report complete for batch #{batch.id}. Email dispatched.")
  end

  private

  def compute_stats(batch)
    items = batch.ingestion_items

    duration_seconds = if batch.started_at && batch.completed_at
                         (batch.completed_at - batch.started_at).to_i
    else
                         0
    end

    # Estimated savings: 5 MB average per duplicate blocked
    duplicate_storage_bytes = batch.duplicate_count.to_i * 5 * 1_024 * 1_024
    estimated_savings_usd   = (duplicate_storage_bytes / (1_024.0 ** 3) * 0.023).round(2)  # ~$0.023/GB S3

    {
      batch_id:           batch.id,
      batch_name:         batch.name,
      source_type:        batch.source_type,
      source_label:       DamProviders.label_for(batch.source_type),
      started_at:         batch.started_at,
      completed_at:       batch.completed_at,
      duration_seconds:   duration_seconds,
      total_assets:       batch.total_count.to_i,
      committed:          batch.committed_count.to_i,
      duplicates_blocked: batch.duplicate_count.to_i,
      errors:             batch.error_count.to_i,
      ready_for_import:   items.where(status: :ready_for_import).count,
      rejected:           items.where(status: :rejected).count,
      ai_enriched:        items.where("clean_properties IS NOT NULL AND clean_properties != '{}'::jsonb").count,
      duplicate_storage_saved_gb: (duplicate_storage_bytes / (1_024.0 ** 3)).round(3),
      estimated_cost_savings_usd: estimated_savings_usd,
      top_errors:         items.where(status: :flagged_error).limit(10).pluck(:original_filename, :error_log),
    }
  end

  def persist_report_snapshot(batch, stats)
    definition = ReportDefinition.find_or_create_by!(
      name:        "migration_batch_summary",
      report_type: "migration"
    ) do |rd|
      rd.active      = true
      rd.query_config = { auto_generated: true }
    end

    snapshot = ReportSnapshot.create!(
      report_definition: definition,
      format:            "json",
      status:            :completed,
      parameters:        { batch_id: batch.id },
    )

    # Store structured stats as the snapshot payload
    # (ReportSnapshot stores result in a text column via the generators)
    snapshot.update_column(:parameters, snapshot.parameters.merge("stats" => stats))

    snapshot
  rescue => e
    Rails.logger.error("[MigrationReport] Could not persist snapshot: #{e.message}")
    nil
  end

  def notify_batch_complete(batch, stats, snapshot)
    # Find the initiating user
    user = User.find_by(id: batch.initiated_by_id) || User.find_by(admin: true)
    return unless user&.email.present?

    # Send through the existing EmailOrchestrator (uses Liquid templates + audit trail)
    EmailOrchestrator.trigger(
      "migration_batch_complete",
      user.email,
      {
        "user"     => { "first_name" => user.display_name },
        "batch"    => {
          "name"              => stats[:batch_name],
          "source"            => stats[:source_label],
          "committed"         => stats[:committed],
          "duplicates_blocked" => stats[:duplicates_blocked],
          "errors"            => stats[:errors],
          "duration_minutes"  => (stats[:duration_seconds] / 60.0).round(1),
          "savings_gb"        => stats[:duplicate_storage_saved_gb],
          "savings_usd"       => stats[:estimated_cost_savings_usd],
          "completed_at"      => stats[:completed_at]&.strftime("%B %d, %Y at %I:%M %p UTC"),
        },
      }
    )
  rescue => e
    Rails.logger.error("[MigrationReport] Email dispatch failed: #{e.message}")
    # Non-fatal — report was still generated
  end
end
