module Api
  module V1
    # Manages global defaults for Collections / Workspaces.
    # Settings are persisted via Setting#get/set (encrypted YAML in PostgreSQL).
    class CollectionSettingsController < ApplicationController
      before_action :authenticate_hybrid!
      before_action :require_admin!,       only: %i[update]
      before_action :require_admin_scope!, only: %i[update]

      SETTING_KEY = "collection_settings"

      DEFAULTS = {
        "default_similarity_threshold" => 0.8,
        "default_visibility"           => "public",
        "max_assets_per_collection"    => 500,
        "auto_cdn_purge"               => true,
        "smart_rule_schedule"          => "daily",
        "ttl_default_days"             => 0,
        "enable_compliance_scan"       => false,
      }.freeze

      # GET /api/v1/collection_settings
      def show
        render json: current_settings
      end

      # PUT /api/v1/collection_settings
      def update
        merged = current_settings.merge(permitted_params)
        Setting.set(SETTING_KEY, merged)
        render json: { settings: merged, message: "Collection settings saved successfully." }
      rescue StandardError => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      private

      def current_settings
        raw = Setting.get(SETTING_KEY) || {}
        DEFAULTS.merge(raw.transform_keys(&:to_s))
      end

      def permitted_params
        params.require(:settings).permit(
          :default_similarity_threshold,
          :default_visibility,
          :max_assets_per_collection,
          :auto_cdn_purge,
          :smart_rule_schedule,
          :ttl_default_days,
          :enable_compliance_scan
        ).to_h.transform_keys(&:to_s)
      end
    end
  end
end
