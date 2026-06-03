class Admin::MigrationsController < ApplicationController
  # before_action :authenticate_user!
  # before_action :require_admin_privileges! # Ensure standard users can't access this

  def ingestion
    # This must perfectly match the `id` in your MenuConfig.js
    # so the sidebar highlights the correct active tab.
    @active_view = 'Ingestion Engine'
  end

  def connectors
    # Matches the ID in MenuConfig.js
    @active_view = 'Legacy Connectors'
  end

  def health
    # Matches the exact ID in MenuConfig.js
    @active_view = 'Data Health'
  end
end