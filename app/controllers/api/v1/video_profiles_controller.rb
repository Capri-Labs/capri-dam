# frozen_string_literal: true

# REST API controller for Video Profiles.
#
# Accessible at +Tools → Assets → Asset Configurations → Video Profiles+.
#
# == Endpoints
#
# | Method | Path | Description |
# |--------|------|-------------|
# | GET    | /api/v1/video_profiles                           | List all active profiles |
# | POST   | /api/v1/video_profiles                           | Create a profile |
# | GET    | /api/v1/video_profiles/:id                       | Show profile + presets |
# | PATCH  | /api/v1/video_profiles/:id                       | Update profile |
# | DELETE | /api/v1/video_profiles/:id                       | Soft-delete profile |
# | POST   | /api/v1/video_profiles/:id/copy                  | Clone a profile |
# | POST   | /api/v1/video_profiles/:id/apply_to_folder       | Assign to folder |
# | DELETE | /api/v1/video_profiles/:id/remove_from_folder    | Remove from folder |
# | GET    | /api/v1/video_profiles/:id/folders               | List assigned folders |
#
# == Authentication
# All actions require +authenticate_hybrid!+. Create/update/delete/copy/assign
# actions additionally require admin privileges.
class Api::V1::VideoProfilesController < ApplicationController
  skip_before_action :verify_authenticity_token, if: -> { request.format.json? }
  before_action :authenticate_hybrid!
  before_action :require_admin!, only: %i[create update destroy copy apply_to_folder remove_from_folder]
  before_action :set_profile,    only: %i[show update destroy copy apply_to_folder remove_from_folder folders]

  # GET /api/v1/video_profiles
  def index
    profiles = VideoProfile.active.order(name: :asc)
    render json: profiles.map { |p| serialize(p) }
  end

  # GET /api/v1/video_profiles/:id
  def show
    render json: serialize(@profile, include_presets: true, include_folders: true)
  end

  # POST /api/v1/video_profiles
  def create
    @profile = VideoProfile.new(profile_params)
    if @profile.save
      render json: serialize(@profile, include_presets: true), status: :created
    else
      render json: { errors: @profile.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /api/v1/video_profiles/:id
  def update
    if @profile.update(profile_params)
      render json: serialize(@profile, include_presets: true)
    else
      render json: { errors: @profile.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/video_profiles/:id
  def destroy
    @profile.soft_delete!
    head :no_content
  end

  # POST /api/v1/video_profiles/:id/copy
  # Clones a profile under a new name (duplicates all encoding presets).
  def copy
    new_name = params[:name].presence || "#{@profile.name} (copy)"
    clone    = @profile.dup
    clone.name       = new_name
    clone.deleted_at = nil

    ActiveRecord::Base.transaction do
      clone.save!
      @profile.encoding_presets.each do |preset|
        clone.encoding_presets << preset.dup
      end
    end

    render json: serialize(clone, include_presets: true), status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: [ e.message ] }, status: :unprocessable_entity
  end

  # POST /api/v1/video_profiles/:id/apply_to_folder
  def apply_to_folder
    folder_id = params[:folder_id]
    return render json: { error: "folder_id is required" }, status: :bad_request if folder_id.blank?

    # Replace any existing video profile assignment for this folder.
    # find_or_create_by!(video_profile_id, folder_id) would create a duplicate row
    # when changing the profile, leaving the old one visible via find_by(folder_id:).
    assignment = nil
    ActiveRecord::Base.transaction do
      VideoProfileFolderAssignment.where(folder_id: folder_id).destroy_all
      assignment = VideoProfileFolderAssignment.create!(
        video_profile_id: @profile.id,
        folder_id:        folder_id
      )
    end
    render json: { profile_id: @profile.id, folder_id: assignment.folder_id }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # DELETE /api/v1/video_profiles/:id/remove_from_folder
  def remove_from_folder
    folder_id = params[:folder_id]
    return render json: { error: "folder_id is required" }, status: :bad_request if folder_id.blank?

    VideoProfileFolderAssignment
      .where(video_profile_id: @profile.id, folder_id: folder_id)
      .destroy_all
    head :no_content
  end

  # GET /api/v1/video_profiles/:id/folders
  def folders
    folder_ids = @profile.folder_assignments.pluck(:folder_id)
    folders    = Folder.where(id: folder_ids).select(:id, :name, :path)
    render json: folders.as_json
  end

  private

  def set_profile
    @profile = VideoProfile.active.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Video profile not found" }, status: :not_found
  end

  def require_admin!
    return if current_user&.admin?

    render json: { error: "Administrator privileges required." }, status: :forbidden
  end

  def profile_params
    parsed_smart_crops = begin
      raw = params.dig(:video_profile, :smart_crop_ratios)
      raw.is_a?(Array) ? raw : (raw.present? ? JSON.parse(raw) : [])
    rescue JSON::ParserError
      []
    end

    permitted = params.require(:video_profile).permit(
      :name,
      :description,
      :encode_for_adaptive_streaming,
      encoding_presets_attributes: %i[
        id name video_format_codec width height keep_aspect_ratio
        video_bitrate_kbps frame_rate_fps audio_codec audio_bitrate_kbps
        two_pass_encoding constant_bitrate h264_profile audio_sampling_rate position _destroy
      ]
    )

    # Parse advanced_params per preset if provided as JSON strings
    if permitted[:encoding_presets_attributes].present?
      Array(permitted[:encoding_presets_attributes]).each do |preset_attrs|
        raw_ap = preset_attrs.delete(:advanced_params)
        next if raw_ap.nil?

        preset_attrs[:advanced_params] = raw_ap.is_a?(Hash) ? raw_ap : begin
          JSON.parse(raw_ap)
        rescue JSON::ParserError
          {}
        end
      end
    end

    permitted[:smart_crop_ratios] = parsed_smart_crops
    permitted
  end

  # ── Serializer ────────────────────────────────────────────────────────────────
  def serialize(profile, include_presets: false, include_folders: false)
    data = {
      id:                            profile.id,
      name:                          profile.name,
      description:                   profile.description,
      encode_for_adaptive_streaming: profile.encode_for_adaptive_streaming,
      smart_crop_ratios:             profile.smart_crop_ratios || [],
      adaptive_streaming_warnings:   profile.adaptive_streaming_warnings,
      folder_count:                  profile.folder_assignments.size,
      created_at:                    profile.created_at,
      updated_at:                    profile.updated_at,
    }

    if include_presets
      data[:encoding_presets] = profile.encoding_presets.map { |p| serialize_preset(p) }
    end

    if include_folders
      folder_ids     = profile.folder_assignments.pluck(:folder_id)
      data[:folders] = Folder.where(id: folder_ids).select(:id, :name, :path).as_json
    end

    data
  end

  def serialize_preset(preset)
    {
      id:                  preset.id,
      name:                preset.name,
      video_format_codec:  preset.video_format_codec,
      width:               preset.width,
      height:              preset.height,
      keep_aspect_ratio:   preset.keep_aspect_ratio,
      video_bitrate_kbps:  preset.video_bitrate_kbps,
      frame_rate_fps:      preset.frame_rate_fps,
      audio_codec:         preset.audio_codec,
      audio_bitrate_kbps:  preset.audio_bitrate_kbps,
      two_pass_encoding:   preset.two_pass_encoding,
      constant_bitrate:    preset.constant_bitrate,
      h264_profile:        preset.h264_profile,
      audio_sampling_rate: preset.audio_sampling_rate,
      advanced_params:     preset.advanced_params || {},
      position:            preset.position,
      size_label:          preset.size_label,
    }
  end
end
