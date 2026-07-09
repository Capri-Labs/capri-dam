class Api::V1::CustomNodeDefinitionsController < ApplicationController
  protect_from_forgery with: :null_session,
                       if: -> { request.format.json? || doorkeeper_token.present? }

  before_action :authenticate_hybrid!
  before_action :require_admin!
  before_action :set_definition, only: %i[show update destroy enable disable]

  def index
    definitions = CustomNodeDefinition.includes(:created_by).order(updated_at: :desc)
    render json: { items: definitions.map { |definition| serialize(definition) } }
  end

  def show
    render json: { custom_node_definition: serialize(@definition) }
  end

  def create
    definition = CustomNodeDefinition.new(definition_params)
    definition.created_by = current_user

    if definition.save
      render json: { custom_node_definition: serialize(definition) }, status: :created
    else
      render json: { errors: definition.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @definition.update(definition_params)
      render json: { custom_node_definition: serialize(@definition) }
    else
      render json: { errors: @definition.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @definition.destroy
    head :no_content
  end

  def enable
    if @definition.update(status: "enabled")
      render json: { custom_node_definition: serialize(@definition) }
    else
      render json: { errors: @definition.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def disable
    @definition.update!(status: "disabled")
    render json: { custom_node_definition: serialize(@definition) }
  end

  private

  def set_definition
    @definition = CustomNodeDefinition.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Custom node definition not found." }, status: :not_found
  end

  def definition_params
    manifest = params.require(:custom_node_definition)
    permitted = manifest.permit(
      :key,
      :name,
      :description,
      :icon,
      :category,
      :color,
      :status,
      runtime: {},
    )
    permitted[:config_schema] = json_value(manifest[:config_schema]) if manifest.key?(:config_schema)
    permitted
  end

  def json_value(value)
    case value
    when ActionController::Parameters
      value.to_unsafe_h
    when Array
      value.map { |entry| json_value(entry) }
    else
      value
    end
  end

  def serialize(definition)
    {
      id: definition.id,
      key: definition.key,
      node_type: definition.node_type,
      name: definition.name,
      description: definition.description,
      icon: definition.icon,
      category: definition.category,
      color: definition.color,
      config_schema: definition.config_schema,
      runtime: safe_runtime(definition.runtime),
      status: definition.status,
      failure_count: definition.failure_count,
      last_error: definition.last_error,
      last_dispatched_at: definition.last_dispatched_at&.iso8601,
      circuit_open: definition.circuit_open?,
      created_by: definition.created_by&.email,
      created_at: definition.created_at&.iso8601,
      updated_at: definition.updated_at&.iso8601,
    }
  end

  def safe_runtime(runtime)
    (runtime || {}).deep_dup.reject { |key, _value| key.to_s.match?(/secret|token|password|credential|api[_-]?key/i) }
  end
end
