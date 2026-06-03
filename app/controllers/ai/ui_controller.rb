class Ai::UiController < ApplicationController
  # before_action :authenticate_user!

  def copilot
    @active_view = 'Semantic Search'
  end

  def agents
    @active_view = 'Agent Automations'
  end

  def batch
    @active_view = 'Metadata Extraction'
  end
end