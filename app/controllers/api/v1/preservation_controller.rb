# frozen_string_literal: true

# REST API for digital-preservation reporting.
#
# == Endpoint summary
#
# | Method | Path                            | Action  | Description                                  |
# |--------|---------------------------------|---------|----------------------------------------------|
# | GET    | /api/v1/preservation/fixity     | fixity  | Estate-wide integrity coverage and failures  |
# | POST   | /api/v1/preservation/verify     | verify  | Verify one asset's versions on demand        |
# | GET    | /api/v1/preservation/formats    | formats | Format obsolescence profile                  |
#
# All actions require an authenticated admin session or admin-scoped bearer
# token: the fixity report names every object the system cannot currently
# account for, which is a map of where to look for gaps.
#
# @see Fixity::Sampler
# @see Fixity::Verifier
# @see Preservation::FormatRegistry
class Api::V1::PreservationController < ApplicationController
  before_action :authenticate_hybrid!
  before_action :require_admin!

  # An on-demand verification downloads the object, so the number of versions
  # one request can trigger is bounded. Without this, a single call against an
  # asset with a long version history is an unbounded egress request.
  MAX_ON_DEMAND_VERSIONS = 25

  # GET /api/v1/preservation/fixity
  #
  # Coverage first, failures second. The headline number an archive is judged
  # on is what proportion of its holdings have *any* recent evidence behind
  # them, not how many checks happened to run last night.
  #
  # @return [void] JSON report
  def fixity
    render json: {
      coverage: Fixity::Sampler.coverage,
      recent_failures: recent_failures,
      last_run_at: FixityCheck.maximum(:checked_at),
      checks_last_24h: FixityCheck.where(checked_at: 24.hours.ago..).count,
      batch_size: Fixity::Sampler::DEFAULT_BATCH_SIZE,
      recheck_after_days: (Fixity::Sampler::DEFAULT_RECHECK_AFTER / 1.day).to_i,
    }
  end

  # POST /api/v1/preservation/verify
  #
  # Runs synchronously and inline. Verification is what the caller is waiting
  # for — deferring it to a job would return "queued" and leave them to poll
  # for an answer that usually arrives in under a second.
  #
  # @return [void] JSON per-version results
  def verify
    asset = Asset.find_by(id: params[:asset_id]) || Asset.find_by(uuid: params[:asset_id])
    return render json: { error: "Asset not found." }, status: :not_found if asset.nil?

    versions = asset.asset_versions.order(version_number: :desc).limit(MAX_ON_DEMAND_VERSIONS)
    results = versions.map { |version| verify_one(version) }

    render json: {
      asset_id: asset.id,
      verified: results.count { |r| r[:status] == "passed" },
      skipped: results.count { |r| r[:status] == "unverifiable" },
      results: results,
    }
  end

  # GET /api/v1/preservation/formats
  #
  # @return [void] JSON format risk profile
  def formats
    render json: Preservation::FormatRegistry.profile
  end

  private

  def verify_one(version)
    result = Fixity::Verifier.call(version)

    if result.nil?
      # No digest or no path: there is nothing to compare against. Reporting
      # this as a pass would be a lie and as a failure would be an alarm.
      {
        version_id: version.id,
        version_number: version.version_number,
        status: "unverifiable",
        message: "No checksum recorded at ingest.",
      }
    else
      {
        version_id: version.id,
        version_number: version.version_number,
        status: result.status,
        message: result.message,
        checked_at: result.check&.checked_at,
      }
    end
  end

  def recent_failures
    FixityCheck.failing.recent.limit(50).map do |check|
      {
        id: check.id,
        asset_id: check.asset_id,
        asset_version_id: check.asset_version_id,
        status: check.status,
        storage_path: check.storage_path,
        storage_backend: check.storage_backend,
        error_message: check.error_message,
        checked_at: check.checked_at,
      }
    end
  end

  def require_admin!
    return if current_user&.admin? || current_user&.super_admin?

    render json: { error: "Administrator privileges required." }, status: :forbidden
  end
end
