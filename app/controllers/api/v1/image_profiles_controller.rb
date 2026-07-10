# frozen_string_literal: true

class Api::V1::ImageProfilesController < ApplicationController
  # Only skip CSRF when the caller authenticates with a bearer token (see
  # ApplicationController#token_authenticated_request?); cookie-session
  # requests still require a valid CSRF token.
  skip_before_action :verify_authenticity_token, if: -> { token_authenticated_request? }
  before_action :authenticate_hybrid!
  before_action :require_admin!, only: %i[create update destroy apply_to_folder remove_from_folder]
  before_action :set_profile,    only: %i[show update destroy apply_to_folder remove_from_folder folders]

  # GET /api/v1/image_profiles
  def index
    profiles = ImageProfile.active.order(name: :asc)
    render json: profiles.map { |p| serialize(p) }
  end

  # GET /api/v1/image_profiles/:id
  def show
    render json: serialize(@profile, include_folders: true)
  end

  # POST /api/v1/image_profiles
  def create
    @profile = ImageProfile.new(profile_params)
    if @profile.save
      render json: serialize(@profile), status: :created
    else
      render json: { errors: @profile.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /api/v1/image_profiles/:id
  def update
    if @profile.update(profile_params)
      render json: serialize(@profile), status: :ok
    else
      render json: { errors: @profile.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/image_profiles/:id
  def destroy
    @profile.soft_delete!
    head :no_content
  end

  # POST /api/v1/image_profiles/:id/apply_to_folder
  def apply_to_folder
    folder_id = params[:folder_id]
    return render json: { error: "folder_id is required" }, status: :bad_request if folder_id.blank?

    # Replace any existing profile assignment for this folder — do NOT use
    # find_or_create_by!(image_profile_id, folder_id): that compound key means
    # "changing" a profile creates a duplicate row; the old row is then returned
    # by find_by(folder_id:), so the UI never reflects the change.
    assignment = nil
    ActiveRecord::Base.transaction do
      ImageProfileFolderAssignment.where(folder_id: folder_id).destroy_all
      assignment = ImageProfileFolderAssignment.create!(
        image_profile_id: @profile.id,
        folder_id:        folder_id
      )
    end
    render json: { profile_id: @profile.id, folder_id: assignment.folder_id }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # DELETE /api/v1/image_profiles/:id/remove_from_folder
  def remove_from_folder
    folder_id = params[:folder_id]
    return render json: { error: "folder_id is required" }, status: :bad_request if folder_id.blank?

    ImageProfileFolderAssignment
      .where(image_profile_id: @profile.id, folder_id: folder_id)
      .destroy_all
    head :no_content
  end

  # GET /api/v1/image_profiles/:id/folders
  def folders
    folder_ids = @profile.folder_assignments.pluck(:folder_id)
    folders    = Folder.where(id: folder_ids).select(:id, :name, :path)
    render json: folders.as_json
  end

  private

  def set_profile
    @profile = ImageProfile.active.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Image profile not found" }, status: :not_found
  end

  def require_admin!
    return if current_user&.admin?

    render json: { error: "Administrator privileges required." }, status: :forbidden
  end

  def profile_params
    # responsive_crops must be pre-parsed JSON array from the frontend
    parsed_crops = begin
      raw = params.dig(:image_profile, :responsive_crops)
      if raw.is_a?(Array)
        raw.map do |crop|
          if crop.respond_to?(:to_unsafe_h)
            crop.to_unsafe_h
          elsif crop.respond_to?(:to_h)
            crop.to_h
          else
            crop
          end
        end
      else
        raw.present? ? JSON.parse(raw) : []
      end
    rescue JSON::ParserError
      []
    end

    permitted = params.require(:image_profile).permit(
      :name, :crop_type, :responsive_crop_enabled,
      :swatch_enabled, :swatch_width, :swatch_height,
      unsharp_mask: %i[amount radius threshold]
    )

    permitted[:responsive_crops] = parsed_crops
    permitted
  end

  # ── Serializer ────────────────────────────────────────────────────────────────
  def serialize(profile, include_folders: false)
    data = {
      id:                      profile.id,
      name:                    profile.name,
      unsharp_mask:            profile.effective_unsharp_mask,
      crop_type:               profile.crop_type,
      responsive_crop_enabled: profile.responsive_crop_enabled,
      responsive_crops:        profile.responsive_crops || [],
      swatch_enabled:          profile.swatch_enabled,
      swatch_width:            profile.swatch_width,
      swatch_height:           profile.swatch_height,
      folder_count:            profile.folder_assignments.size,
      created_at:              profile.created_at,
      updated_at:              profile.updated_at,
    }

    if include_folders
      folder_ids   = profile.folder_assignments.pluck(:folder_id)
      data[:folders] = Folder.where(id: folder_ids).select(:id, :name, :path).as_json
    end

    data
  end
end
