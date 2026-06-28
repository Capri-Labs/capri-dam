# frozen_string_literal: true

# HTML-shell controller for AI feature screens.  Each action renders a minimal
# ERB view that mounts the corresponding React component via the COMPONENT_REGISTRY.
#
# Authentication:
#   - All actions require a valid Devise session (authenticate_user!).
#   - Screens that configure AI behaviour (Agent Automations, Batch Processing,
#     Prompt Playground) are restricted to admin users (require_admin!).
#   - The Semantic Copilot is available to every authenticated user.
class Ai::UiController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin!, only: %i[agents batch playground]

  def copilot
    @active_view = "Semantic Search"
  end

  def agents
    @active_view = "Agent Automations"
  end

  def batch
    @active_view = "Metadata Extraction"
  end

  def playground
    @active_view = "Prompt Playground"
  end
end
