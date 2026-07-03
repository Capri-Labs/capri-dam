# frozen_string_literal: true

# Background worker that executes data-health remediation tasks on behalf of
# an admin user.  Each task is identified by a +debt_type+ string and performs
# a targeted clean-up or flagging action.
#
# == Supported debt types
#
# | Type             | Action                                                    |
# |------------------|-----------------------------------------------------------|
# | duplicates       | Triggers a full duplicate-repository scan                 |
# | missing_metadata | Queues PreFlightAnalysisWorker for every active connector |
# | copyright        | Flags assets without a copyright property                 |
# | stale            | (future) Marks assets unaccessed > 3 years                |
#
# == Queue & retry
#
# * Queue:   +ingest+
# * Retries: 1 — remediation jobs are admin-initiated and rare
#
# @see Api::V1::DataHealthController#remediate
# @see DuplicateRepositoryScanWorker
# @see PreFlightAnalysisWorker
class DataHealthRemediationWorker
  include Sidekiq::Worker

  sidekiq_options queue: "ingest", retry: 1

  # All valid debt types accepted by this worker.
  DEBT_TYPES = %w[duplicates missing_metadata copyright stale].freeze

  # @param debt_type [String]  one of {DEBT_TYPES}
  # @param user_id   [Integer] admin user who triggered the action
  # @return [void]
  def perform(debt_type, user_id)
    Rails.logger.info(
      "[DataHealthRemediationWorker] Starting remediation for debt_type=#{debt_type} " \
      "initiated_by=#{user_id}"
    )

    case debt_type
    when "duplicates"
      remediate_duplicates
    when "missing_metadata"
      remediate_missing_metadata
    when "copyright"
      remediate_copyright
    when "stale"
      remediate_stale
    else
      Rails.logger.warn("[DataHealthRemediationWorker] Unknown debt_type: #{debt_type}")
    end

    Rails.logger.info(
      "[DataHealthRemediationWorker] Remediation complete for debt_type=#{debt_type}"
    )
  rescue StandardError => e
    Rails.logger.error(
      "[DataHealthRemediationWorker] Failed for debt_type=#{debt_type}: " \
      "#{e.class}: #{e.message}"
    )
    raise
  end

  private

  # Triggers a full repository scan to (re)build duplicate groups.
  def remediate_duplicates
    current = Setting.get("duplicate_manager_scan_status").to_s
    if current == "running" && DuplicateRepositoryScanWorker.scan_running?
      Rails.logger.info("[DataHealthRemediationWorker] Duplicate scan already running, skipping.")
      return
    elsif current == "queued"
      Rails.logger.info("[DataHealthRemediationWorker] Duplicate scan already queued, skipping.")
      return
    end
    Setting.set("duplicate_manager_scan_status", "queued")
    DuplicateRepositoryScanWorker.perform_async
    Rails.logger.info("[DataHealthRemediationWorker] DuplicateRepositoryScanWorker enqueued.")
  end

  # Queues a PreFlightAnalysisWorker for every active SystemConnector so
  # their analysis_report is refreshed with the latest metadata-quality stats.
  def remediate_missing_metadata
    active_connectors = SystemConnector.where(status: "active")
    if active_connectors.empty?
      Rails.logger.info("[DataHealthRemediationWorker] No active connectors for pre-flight scan.")
      return
    end

    active_connectors.find_each do |connector|
      PreFlightAnalysisWorker.perform_async(connector.id)
    end

    Rails.logger.info(
      "[DataHealthRemediationWorker] PreFlightAnalysisWorker queued for " \
      "#{active_connectors.count} connector(s)."
    )
  end

  # Tags assets that have no copyright property so they are surfaced
  # in the compliance queue.  Adds a flag property rather than deleting
  # anything — reversible.
  def remediate_copyright
    flagged = 0

    Asset.where("properties->>'copyright' IS NULL")
         .find_each(batch_size: 200) do |asset|
      asset.update_columns(
        properties: asset.properties.merge("tdm_copyright_flagged" => true, "tdm_flagged_at" => Time.current.iso8601)
      )
      flagged += 1
    end

    Rails.logger.info(
      "[DataHealthRemediationWorker] Flagged #{flagged} asset(s) for missing copyright."
    )
  end

  # Placeholder for stale-asset remediation (e.g., move to cold storage).
  # The actual implementation depends on storage backend configuration.
  def remediate_stale
    stale_count = Asset.where("last_accessed_at < ?", 3.years.ago).count
    Rails.logger.info(
      "[DataHealthRemediationWorker] Stale remediation: #{stale_count} candidate asset(s). " \
      "Manual review required — no automated archival in this environment."
    )
  end
end
