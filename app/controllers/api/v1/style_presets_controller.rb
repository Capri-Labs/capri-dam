# frozen_string_literal: true

# REST API for Style Presets (Style & Model Hub — /ai/models/hub).
#
# == Endpoint summary
#
# | Method | Path                                    | Action      | Auth  |
# |--------|-----------------------------------------|-------------|-------|
# | GET    | /api/v1/style_presets                   | index       | admin |
# | POST   | /api/v1/style_presets                   | create      | admin |
# | GET    | /api/v1/style_presets/:id               | show        | admin |
# | PATCH  | /api/v1/style_presets/:id               | update      | admin |
# | DELETE | /api/v1/style_presets/:id               | destroy     | admin |
# | POST   | /api/v1/style_presets/:id/sync          | sync        | admin |
# | POST   | /api/v1/style_presets/:id/set_default   | set_default | admin |
class Api::V1::StylePresetsController < ApplicationController
  before_action :authenticate_hybrid!
  before_action :require_admin!
  before_action :set_preset, only: %i[show update destroy sync set_default]

  # GET /api/v1/style_presets
  def index
    presets = StylePreset.includes(:created_by).recent
    presets = presets.active if params[:active] == "true"

    render json: {
      total:   presets.count,
      presets: presets.map { |p| serialize(p) },
    }
  end

  # GET /api/v1/style_presets/:id
  def show
    render json: serialize(@preset)
  end

  # POST /api/v1/style_presets
  def create
    preset = StylePreset.new(preset_params)
    preset.created_by = current_user
    if preset.save
      render json: serialize(preset), status: :created
    else
      render json: { errors: preset.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH /api/v1/style_presets/:id
  def update
    if @preset.update(preset_params)
      render json: serialize(@preset)
    else
      render json: { errors: @preset.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/style_presets/:id
  def destroy
    @preset.destroy!
    render json: { message: "Style preset deleted." }
  end

  # POST /api/v1/style_presets/:id/sync
  # Enqueues a sync of this preset to the AI Gateway.
  def sync
    StylePresetSyncWorker.perform_async(@preset.id)
    render json: { message: "Sync queued for '#{@preset.name}'." }
  end

  # POST /api/v1/style_presets/:id/set_default
  def set_default
    @preset.promote_to_default!
    render json: serialize(@preset)
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  private

  def set_preset
    @preset = StylePreset.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Style preset not found." }, status: :not_found
  end

  def preset_params
    params.require(:style_preset).permit(
      :name, :slug, :description, :active, :is_default,
      style_params: {},
    )
  end

  def serialize(preset)
    {
      id:           preset.id,
      name:         preset.name,
      slug:         preset.slug,
      description:  preset.description,
      active:       preset.active,
      is_default:   preset.is_default,
      style_params: preset.style_params,
      gateway_ref:  preset.gateway_ref,
      synced_at:    preset.synced_at,
      stale:        preset.stale?,
      created_by:   preset.created_by&.email,
      created_at:   preset.created_at,
      updated_at:   preset.updated_at,
    }
  end
end
