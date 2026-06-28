# frozen_string_literal: true

# HTML-shell controller for AI feature screens.  Each action renders a minimal
# ERB view that mounts the corresponding React component via the COMPONENT_REGISTRY.
#
# Authentication:
#   - All actions require a valid Devise session (authenticate_user!).
#   - Screens that configure AI behaviour (Agent Automations, AI Batch Tasks,
#     Prompt Playground) are restricted to admin users (require_admin!).
#   - The Semantic Copilot is available to every authenticated user.
class Ai::UiController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin!, only: %i[agents tasks playground provenance style_model_hub]

  def copilot
    @active_view = "Semantic Search"
  end

  def agents
    @active_view = "Agent Automations"
  end

  def tasks
    @active_view = "AI Batch Tasks"
  end

  def playground
    @active_view = "Prompt Playground"
  end

  def provenance
    @active_view = "Provenance & C2PA"
  end

  def style_model_hub
    @active_view = "Brand Synthesis"
  end
end
