# frozen_string_literal: true

# REST API controller for the TDM & Storage Health dashboard.
#
# == Endpoint summary
#
# | Method | Path                           | Action      | Description                               |
# |--------|--------------------------------|-------------|-------------------------------------------|
# | GET    | /api/v1/data_health/overview   | overview    | Aggregate health metrics (fast)           |
# | GET    | /api/v1/data_health/connectors | connectors  | Per-connector health + pre-flight reports |
# | POST   | /api/v1/data_health/remediate  | remediate   | Queue a background remediation job        |
#
# All actions require an authenticated admin session or admin-scoped bearer token.
#
# @see DataHealthRemediationWorker
# @see PreFlightAnalysisWorker
# @see IngestionBatch.aggregate_stats
# @see DuplicateGroup
class Api::V1::DataHealthController < ApplicationController
  before_action :authenticate_hybrid!
  before_action :require_admin!

  # GET /api/v1/data_health/overview
  #
  # Single aggregate payload for dashboard metric cards, storage composition
  # bar, and debt-flag list. Runs cheap aggregate SQL queries.
  #
  # @return [void] JSON overview object
  def overview
    batch_stats = IngestionBatch.aggregate_stats
    dup_stats   = duplicate_group_stats
    scan        = current_scan_status

    connector_counts = SystemConnector
      .group(:status)
      .count
      .with_defaults("active" => 0, "idle" => 0, "disabled" => 0)

    render json: {
      storage:     build_storage_metrics(batch_stats),
      duplicates:  dup_stats,
      connectors:  {
        total:    SystemConnector.count,
        active:   connector_counts["active"],
        idle:     connector_counts["idle"],
        disabled: connector_counts["disabled"],
      },
      batches:     build_batch_overview(batch_stats),
      scan:        scan,
      debt_flags:  build_debt_flags(dup_stats, batch_stats),
      generated_at: Time.current.iso8601,
    }
  end

  # GET /api/v1/data_health/connectors
  #
  # Returns every SystemConnector with health attributes: status,
  # assets_imported, last_sync, analysis_report, batch count.
  #
  # @return [void] JSON array
  def connectors
    conns = SystemConnector.order(:name).includes(:ingestion_batches)
    render json: conns.map { |c| serialize_connector_health(c) }
  end

  # POST /api/v1/data_health/remediate
  #
  # Queues a {DataHealthRemediationWorker} job.
  # Returns +422+ if the debt_type is unknown.
  #
  # @return [void] +202 Accepted+ or +422 Unprocessable Entity+
  def remediate
    debt_type = params[:debt_type].to_s.strip

    unless DataHealthRemediationWorker::DEBT_TYPES.include?(debt_type)
      return render json: {
        error: "Unknown debt type '#{debt_type}'. " \
               "Valid types: #{DataHealthRemediationWorker::DEBT_TYPES.join(", ")}",
      }, status: :unprocessable_entity
    end

    DataHealthRemediationWorker.perform_async(debt_type, current_user.id)
    render json: { message: "Remediation job queued for '#{debt_type}'." }, status: :accepted
  end

  private

  # ── Metric builders ──────────────────────────────────────────────────────────

  def build_storage_metrics(batch_stats)
    prevented_bytes = IngestionItem
      .where(status: IngestionItem.statuses[:flagged_duplicate])
      .sum(:file_size)
    active_bytes    = Asset.sum(:file_size)
    orphaned_bytes  = Asset.left_outer_joins(:collection_assets)
                           .where(collection_assets: { id: nil })
                           .sum(:file_size)

    {
      duplicates_prevented_tb:  bytes_to_tb(prevented_bytes),
      active_used_tb:           bytes_to_tb(active_bytes),
      orphaned_wasted_tb:       bytes_to_tb(orphaned_bytes),
      total_duplicates_blocked: batch_stats[:total_duplicates_blocked],
      total_assets_committed:   batch_stats[:total_assets_committed],
      total_assets_staged:      batch_stats[:total_assets_staged],
      estimated_savings_gb:     batch_stats[:estimated_storage_saved_gb],
      estimated_savings_usd_mo: batch_stats[:estimated_cost_savings_usd],
    }
  end

  def build_batch_overview(batch_stats)
    {
      total:     batch_stats[:total_batches],
      active:    batch_stats[:active_batches],
      completed: batch_stats[:completed_batches],
      failed:    batch_stats[:failed_batches],
    }
  end

  def duplicate_group_stats
    counts = DuplicateGroup.group(:status).count
    {
      pending:   counts["pending"].to_i,
      resolved:  counts["resolved"].to_i,
      dismissed: counts["dismissed"].to_i,
      total:     counts.values.sum,
    }
  end

  def current_scan_status
    raw_progress = Setting.get("duplicate_manager_scan_progress")
    progress     = raw_progress.is_a?(Hash) ? raw_progress : {}
    {
      status:      Setting.get("duplicate_manager_scan_status").to_s.presence || "idle",
      progress:    progress,
      last_scan_at: Setting.get("duplicate_manager_last_scan_at"),
    }
  end

  # Builds the live debt-flag list for the Debt Remediation tab.
  def build_debt_flags(dup_stats, batch_stats)
    pending_dupes    = dup_stats[:pending]
    review_needed    = IngestionBatch.where(status: IngestionBatch.statuses["review_needed"]).count
    missing_metadata = SystemConnector
      .where.not(analysis_report: nil)
      .sum { |c| c.analysis_report&.dig("missing_tags").to_i }
    copyright_gaps   = Asset.where("properties->>'copyright' IS NULL").count

    [
      {
        type:         "duplicates",
        title:        "Confirmed Duplicate Asset Groups",
        description:  "SHA-256-matched asset groups pending admin resolution. " \
                      "Resolving frees storage and prevents reference rot.",
        count:        pending_dupes,
        impact:       debt_impact(pending_dupes, critical: 500, high: 100),
        action_label: "Resolve in Duplicate Manager",
        action_link:  "/admin/duplicates",
        actionable:   pending_dupes > 0,
        can_automate: false,
      },
      {
        type:         "missing_metadata",
        title:        "Assets Missing Mandatory Metadata",
        description:  "Assets flagged during connector pre-flight analysis as " \
                      "missing required tags (title, rights, usage type).",
        count:        missing_metadata,
        impact:       debt_impact(missing_metadata, critical: 1000, high: 200),
        action_label: "Run Pre-Flight Scans",
        action_link:  "/admin/migrations/connectors",
        actionable:   true,
        can_automate: true,
        remediation:  "missing_metadata",
      },
      {
        type:         "copyright",
        title:        "Missing Copyright / Usage Rights",
        description:  "Assets without a copyright property — a legal and " \
                      "compliance risk for regulated industries.",
        count:        copyright_gaps,
        impact:       copyright_gaps > 500 ? "Critical" : copyright_gaps > 50 ? "High" : "Medium",
        action_label: "Flag for Legal Review",
        action_link:  "/admin/migrations/health",
        actionable:   copyright_gaps > 0,
        can_automate: true,
        remediation:  "copyright",
      },
      {
        type:         "review_pipeline",
        title:        "Migration Batches Awaiting Review",
        description:  "Ingestion batches in review_needed state require human " \
                      "approval before assets are committed to the live DAM.",
        count:        review_needed,
        impact:       review_needed > 5 ? "High" : review_needed > 0 ? "Medium" : "None",
        action_label: "Go to Migration Pipeline",
        action_link:  "/admin/migrations/ingestion",
        actionable:   review_needed > 0,
        can_automate: false,
      },
    ]
  end

  def serialize_connector_health(connector)
    report = connector.analysis_report

    {
      id:              connector.id,
      name:            connector.name,
      provider_type:   connector.provider_type,
      provider_label:  connector.provider_label,
      status:          connector.status,
      assets_imported: connector.assets_imported.to_i,
      last_sync:       connector.last_sync&.iso8601,
      tdm_sanitation:  connector.tdm_sanitation,
      batches_count:   connector.ingestion_batches.size,
      analysis_report: report,
      health_score:    compute_health_score(connector, report),
    }
  end

  # Returns a 0–100 integer health score based on connector state.
  def compute_health_score(connector, report)
    return nil if connector.status == "disabled"

    score = 100
    score -= 40 if connector.status != "active"
    score -= 20 if connector.last_sync.nil?
    score -= 20 if connector.last_sync.present? && connector.last_sync < 7.days.ago

    if report.present?
      total   = report["total_found"].to_i
      missing = report["missing_tags"].to_i
      score  -= 20 if total > 0 && (missing.to_f / total) > 0.25
    else
      score -= 10
    end

    [ score, 0 ].max
  end

  def bytes_to_tb(bytes)
    (bytes.to_f / (1024**4)).round(4)
  end

  # @param count   [Integer]
  # @param critical [Integer] threshold for Critical
  # @param high     [Integer] threshold for High
  def debt_impact(count, critical:, high:)
    if count > critical    then "Critical"
    elsif count > high     then "High"
    elsif count > 0        then "Medium"
    else                        "None"
    end
  end
end
