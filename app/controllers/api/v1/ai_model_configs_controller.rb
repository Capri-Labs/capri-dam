# frozen_string_literal: true

# REST API for the AI Model Config registry (Style & Model Hub — /ai/models/hub).
#
# == Endpoint summary
#
# | Method | Path                                          | Action           | Auth           |
# |--------|-----------------------------------------------|------------------|----------------|
# | GET    | /api/v1/ai_model_configs                      | index            | admin          |
# | POST   | /api/v1/ai_model_configs                      | create           | admin          |
# | GET    | /api/v1/ai_model_configs/:id                  | show             | admin          |
# | PATCH  | /api/v1/ai_model_configs/:id                  | update           | admin          |
# | DELETE | /api/v1/ai_model_configs/:id                  | destroy          | admin          |
# | POST   | /api/v1/ai_model_configs/:id/health_check     | health_check     | admin          |
# | POST   | /api/v1/ai_model_configs/:id/set_default      | set_default      | admin          |
# | POST   | /api/v1/ai_model_configs/:id/health_callback  | health_callback  | gateway secret |
# | GET    | /api/v1/ai_model_configs/capabilities         | capabilities     | admin          |
class Api::V1::AiModelConfigsController < ApplicationController
  before_action :authenticate_hybrid!, except: %i[health_callback]
  before_action :require_admin!,       except: %i[health_callback]
  before_action :authenticate_gateway_secret!, only: %i[health_callback]
  before_action :set_config, only: %i[show update destroy health_check set_default health_callback]

  # GET /api/v1/ai_model_configs
  def index
    configs = AiModelConfig.order(capability: :asc, name: :asc)
    configs = configs.where(capability: params[:capability]) if params[:capability].present?
    configs = configs.where(enabled: params[:enabled] == "true") if params[:enabled].present?

    render json: {
      total:   configs.count,
      configs: configs.map { |c| serialize(c) },
    }
  end

  # GET /api/v1/ai_model_configs/capabilities
  def capabilities
    render json: {
      capabilities: AiModelConfig::CAPABILITIES,
      providers:    AiModelConfig::PROVIDERS,
      health_statuses: AiModelConfig::HEALTH_STATUSES,
    }
  end

  # GET /api/v1/ai_model_configs/:id
  def show
    render json: serialize(@config)
  end

  # POST /api/v1/ai_model_configs
  def create
    config = AiModelConfig.new(config_params)
    if config.save
      render json: serialize(config), status: :created
    else
      render json: { errors: config.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH /api/v1/ai_model_configs/:id
  def update
    if @config.update(config_params)
      render json: serialize(@config)
    else
      render json: { errors: @config.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/ai_model_configs/:id
  def destroy
    @config.destroy!
    render json: { message: "Model config deleted." }
  end

  # POST /api/v1/ai_model_configs/:id/health_check
  # Enqueues a health-check ping to the gateway for this model.
  def health_check
    AiModelHealthCheckWorker.perform_async(@config.id)
    render json: { message: "Health check queued for #{@config.name}." }
  end

  # POST /api/v1/ai_model_configs/:id/set_default
  def set_default
    @config.promote_to_default!
    render json: serialize(@config)
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  # POST /api/v1/ai_model_configs/:id/health_callback
  # Called by the AI Gateway after a health-check ping.
  # Authentication: X-Gateway-Secret header only — no Devise session required.
  def health_callback
    permitted = params.require(:health).permit(:health_status, :health_latency_ms, :error_message)
    @config.update!(
      health_status:       permitted[:health_status].presence || "unknown",
      health_latency_ms:   permitted[:health_latency_ms].to_i,
      error_message:       permitted[:error_message],
      last_health_check_at: Time.current,
    )
    render json: serialize(@config)
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  private

  def set_config
    @config = AiModelConfig.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: "AI model config not found." }, status: :not_found
  end

  def config_params
    params.require(:ai_model_config).permit(
      :name, :provider, :model_id, :capability, :enabled, :is_default,
      config_params: {},
      metadata: {},
    )
  end

  def serialize(config)
    {
      id:                   config.id,
      name:                 config.name,
      provider:             config.provider,
      model_id:             config.model_id,
      capability:           config.capability,
      enabled:              config.enabled,
      is_default:           config.is_default,
      config_params:        config.config_params,
      health_status:        config.health_status,
      health_latency_ms:    config.health_latency_ms,
      last_health_check_at: config.last_health_check_at,
      error_message:        config.error_message,
      metadata:             config.metadata,
      created_at:           config.created_at,
      updated_at:           config.updated_at,
    }
  end

  def authenticate_gateway_secret!
    expected = Rails.application.credentials.dig(:ai_gateway, :secret).presence ||
               ENV.fetch("GATEWAY_SECRET", nil)
    received = request.headers["X-Gateway-Secret"]

    return if expected.present? && ActiveSupport::SecurityUtils.secure_compare(expected, received.to_s)

    render json: { error: "Unauthorized" }, status: :unauthorized
  end
end
