# frozen_string_literal: true

# REST endpoints for per-asset C2PA / Content Provenance records.
#
# | Method | Path                                             | Auth           |
# |--------|--------------------------------------------------|----------------|
# | GET    | /api/v1/asset_provenance_records                 | admin          |
# | GET    | /api/v1/asset_provenance_records/stats           | admin          |
# | GET    | /api/v1/asset_provenance_records/:id             | admin          |
# | POST   | /api/v1/asset_provenance_records/bulk_upsert     | gateway secret |
#
# The `bulk_upsert` endpoint is machine-to-machine: the AI Gateway calls it
# after processing a batch of assets (c2pa_verify, c2pa_sign, disclosure.audit).
# Authentication is via the shared `X-Gateway-Secret` header only.
class Api::V1::AssetProvenanceRecordsController < ApplicationController
  before_action :authenticate_hybrid!,        except: %i[bulk_upsert]
  before_action :require_admin!,              except: %i[bulk_upsert]
  before_action :authenticate_gateway_secret!, only: %i[bulk_upsert]

  PAGE_SIZE = 50

  # GET /api/v1/asset_provenance_records
  def index
    page  = (params[:page].presence || 1).to_i.clamp(1, 10_000)
    scope = AssetProvenanceRecord.includes(:asset).recent

    scope = scope.where(manifest_status: params[:status])  if params[:status].present?
    scope = scope.where(is_ai_modified: true)              if params[:ai_modified] == "true"

    total   = scope.count
    records = scope.limit(PAGE_SIZE).offset((page - 1) * PAGE_SIZE)

    render json: {
      total:    total,
      page:     page,
      per_page: PAGE_SIZE,
      records:  records.map { |r| serialize(r) },
    }
  end

  # GET /api/v1/asset_provenance_records/stats
  # Dashboard summary counts for the Provenance & C2PA screen.
  def stats
    render json: {
      total_assets: Asset.active.count,
      verified:     AssetProvenanceRecord.verified.count,
      ai_modified:  AssetProvenanceRecord.ai_modified.count,
      ai_flagged:   AssetProvenanceRecord.ai_flagged.count,
      missing:      AssetProvenanceRecord.missing.count,
      invalid:      AssetProvenanceRecord.invalid_manifest.count,
      signed:       AssetProvenanceRecord.signed.count,
      unchecked:    AssetProvenanceRecord.unchecked.count,
    }
  end

  # GET /api/v1/asset_provenance_records/:id
  def show
    record = AssetProvenanceRecord.includes(:asset).find(params[:id])
    render json: serialize(record)
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Provenance record not found." }, status: :not_found
  end

  # POST /api/v1/asset_provenance_records/bulk_upsert
  #
  # Called by the AI Gateway to write per-asset C2PA verification / signing
  # results back to Rails.  Uses PostgreSQL upsert (ON CONFLICT DO UPDATE) for
  # idempotency — safe to call multiple times with the same data.
  def bulk_upsert
    raw_records = params[:records]
    if raw_records.blank?
      return render json: { error: "records array is required" }, status: :unprocessable_entity
    end

    now      = Time.current
    rows     = []
    skipped  = 0

    Array.wrap(raw_records).each do |r|
      asset_id = resolve_asset_id(r[:asset_id] || r["asset_id"])
      unless asset_id
        skipped += 1
        next
      end

      rows << {
        asset_id:                asset_id,
        manifest_status:         sanitize_status(r[:manifest_status] || r["manifest_status"]),
        manifest_data:           (r[:manifest_data] || r["manifest_data"])&.to_unsafe_h || {},
        claim_generator:         r[:claim_generator]  || r["claim_generator"],
        is_ai_modified:          ActiveModel::Type::Boolean.new.cast(r[:is_ai_modified] || r["is_ai_modified"]) || false,
        ai_tools_used:           (r[:ai_tools_used] || r["ai_tools_used"] || []).to_a,
        verified_at:             r[:verified_at]             || r["verified_at"],
        signed_at:               r[:signed_at]               || r["signed_at"],
        signer_name:             r[:signer_name]             || r["signer_name"],
        signer_cert_fingerprint: r[:signer_cert_fingerprint] || r["signer_cert_fingerprint"],
        error_detail:            r[:error_detail]            || r["error_detail"],
        created_at:              now,
        updated_at:              now,
      }
    end

    return render json: { error: "No valid records after resolving asset IDs.", skipped: skipped },
                  status: :unprocessable_entity if rows.empty?

    result = AssetProvenanceRecord.upsert_all(
      rows,
      unique_by: :index_asset_provenance_records_on_asset_id,
      update_only: %i[
        manifest_status manifest_data claim_generator is_ai_modified ai_tools_used
        verified_at signed_at signer_name signer_cert_fingerprint error_detail updated_at
      ],
      record_timestamps: false
    )

    render json: { upserted: result.length, skipped: skipped }
  end

  private

  # Resolve an asset UUID string to the asset's UUID primary key
  def resolve_asset_id(raw)
    return nil if raw.blank?
    Asset.find_by(uuid: raw)&.id || Asset.find_by(id: raw)&.id
  end

  def sanitize_status(raw)
    AssetProvenanceRecord::MANIFEST_STATUSES.include?(raw.to_s) ? raw.to_s : "unchecked"
  end

  def authenticate_gateway_secret!
    expected = Rails.application.credentials.dig(:ai_gateway, :secret).presence ||
               ENV.fetch("GATEWAY_SECRET", nil)
    received = request.headers["X-Gateway-Secret"]

    return if expected.present? && ActiveSupport::SecurityUtils.secure_compare(expected, received.to_s)

    render json: { error: "Unauthorized" }, status: :unauthorized
  end

  def serialize(record)
    {
      id:                      record.id,
      asset_id:                record.asset_id,
      asset_uuid:              record.asset&.uuid,
      asset_title:             record.asset&.title,
      manifest_status:         record.manifest_status,
      manifest_data:           record.manifest_data,
      claim_generator:         record.claim_generator,
      is_ai_modified:          record.is_ai_modified,
      ai_tools_used:           record.ai_tools_used,
      verified_at:             record.verified_at,
      signed_at:               record.signed_at,
      signer_name:             record.signer_name,
      signer_cert_fingerprint: record.signer_cert_fingerprint,
      error_detail:            record.error_detail,
      created_at:              record.created_at,
      updated_at:              record.updated_at,
    }
  end
end
