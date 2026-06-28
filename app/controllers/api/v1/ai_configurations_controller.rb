class Api::V1::AiConfigurationsController < ApplicationController
  before_action :authenticate_hybrid!
  before_action :require_admin!, only: %i[update]
  before_action :require_admin_scope!, only: %i[update]

  def show
    render json: AiConfiguration.current
  end

  def update
    config = AiConfiguration.current
    if config.update(configuration_params)
      render json: { message: "AI Gateway Configuration synchronized successfully.", config: config }
    else
      render json: { errors: config.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def configuration_params
    params.require(:ai_configuration).permit(
      :active_provider, :generation_model, :embedding_model,
      :monthly_budget_usd, :system_prompt, :fallback_to_local
    )
  end
end
