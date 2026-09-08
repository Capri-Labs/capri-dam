# Manual CRUD for {Rendition} rows — the alternative forms of an asset that a
# person uploads rather than the pipeline produces: a print-ready CMYK TIFF, a
# hand-cropped social variant, a signed-off proof PDF.
#
# WHY MANUAL RENDITIONS EXIST AT ALL
# ----------------------------------
# The processing pipeline can only produce what it knows how to produce. The
# forms that matter most to a brand team are usually the ones that required a
# human — a crop that keeps the logo intact, a colour profile a client
# stipulated. Without somewhere to put those, they end up as separate assets
# whose relationship to the original lives only in a filename convention.
#
# PERMISSIONS
# -----------
# Reading a rendition needs +:read+ on the asset; creating or deleting one needs
# +:modify+. Adding a rendition changes what the asset *is* to every downstream
# consumer, so it is not a read-adjacent act.
class Api::V1::RenditionsController < ApplicationController
  before_action :authenticate_hybrid!
  before_action :set_asset

  # GET /api/v1/assets/:asset_id/renditions
  def index
    check_asset_read!(@asset)
    return if performed?

    renditions = @asset.renditions.includes(:storage_backend).order(:kind)

    render json: {
      renditions: renditions.map { |r| serialize(r) },
      meta: { total: renditions.size },
    }
  end

  # POST /api/v1/assets/:asset_id/renditions  (multipart/form-data)
  #
  # Parameters:
  # * +file+     — the binary upload (required)
  # * +kind+     — e.g. "print_cmyk" (required, not one of {Rendition::SYSTEM_KINDS})
  # * +metadata+ — optional JSON object or nested form params
  def create
    check_asset_modify!(@asset)
    return if performed?

    file = params[:file]
    return render(json: { error: "A file is required." }, status: :unprocessable_entity) if file.blank?
    return if reject_system_kind!
    return if reject_oversize!(file)

    result = Renditions::Uploader.new(
      asset: @asset,
      file: file,
      kind: params[:kind],
      metadata: submitted_metadata,
    ).call

    if result.rendition.persisted?
      render json: serialize(result.rendition), status: :created
    else
      render json: { errors: result.rendition.errors.full_messages }, status: :unprocessable_entity
    end
  rescue Renditions::Uploader::UnavailableBackendError => e
    # A configuration problem, not a bad request — but the caller still needs to
    # be told plainly, because retrying identically will not help.
    render json: { error: e.message }, status: :service_unavailable
  end

  # DELETE /api/v1/assets/:asset_id/renditions/:id
  #
  # Destroys the row *and* the stored object — see {Rendition}. There is no
  # soft-delete here: unlike an asset, a rendition carries no history of its
  # own, so a hidden row would be a file nobody can see and nobody can reclaim.
  def destroy
    check_asset_modify!(@asset)
    return if performed?

    rendition = @asset.renditions.find_by(id: params[:id])
    return render(json: { error: "Rendition not found" }, status: :not_found) if rendition.nil?

    rendition.destroy!
    render json: { id: rendition.id, deleted: true }
  end

  private

  def set_asset
    @asset = Asset.find_by(id: params[:asset_id]) || Asset.find_by(uuid: params[:asset_id])
    render json: { error: "Asset not found" }, status: :not_found if @asset.nil?
  end

  # The pipeline owns these names and other code trusts them; a hand-uploaded
  # file must not be able to present itself as a generated thumbnail.
  def reject_system_kind!
    return false unless Rendition::SYSTEM_KINDS.include?(params[:kind].to_s.strip.downcase)

    render json: {
      error: "'#{params[:kind]}' is generated automatically and cannot be uploaded manually.",
      reserved_kinds: Rendition::SYSTEM_KINDS,
    }, status: :unprocessable_entity
    true
  end

  def reject_oversize!(file)
    limit = max_upload_size_bytes
    return false unless file.respond_to?(:size) && file.size.to_i > limit

    render json: {
      error: "File exceeds the maximum upload size of #{(limit / 1.gigabyte.to_f).round(2)} GB.",
      max_upload_size_bytes: limit,
    }, status: :payload_too_large
    true
  end

  def max_upload_size_bytes
    configured = Setting.get("max_upload_size_bytes")
    configured.present? ? configured.to_i : 2.gigabytes
  end

  def submitted_metadata
    raw = params[:metadata]
    case raw
    when ActionController::Parameters then raw.to_unsafe_h
    when Hash then raw
    when String then (JSON.parse(raw) rescue {})
    else {}
    end
  end

  # +storage_key+ is deliberately absent: it is an internal address, and
  # publishing it invites callers to build their own URLs against a backend
  # whose layout is not part of the contract.
  def serialize(rendition)
    {
      id: rendition.id,
      asset_id: rendition.asset_id,
      kind: rendition.kind,
      content_type: rendition.content_type,
      width: rendition.width,
      height: rendition.height,
      file_size: rendition.file_size,
      source: rendition.manual? ? "manual" : "generated",
      storage_backend: rendition.storage_backend&.name,
      metadata: rendition.metadata,
      url: rendition_url_for(rendition),
      created_at: rendition.created_at,
    }
  end

  # A broken backend should not turn a listing into a 500; a rendition whose
  # URL cannot currently be resolved is still a rendition worth reporting.
  def rendition_url_for(rendition)
    rendition.url
  rescue StandardError => e
    Rails.logger.warn("Rendition #{rendition.id}: cannot resolve URL: #{e.message}")
    nil
  end
end
