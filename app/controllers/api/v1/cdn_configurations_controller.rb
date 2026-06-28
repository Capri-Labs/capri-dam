module Api
  module V1
    class CdnConfigurationsController < ApplicationController
      before_action :authenticate_hybrid!
      before_action :require_admin!, only: %i[update]

      def index
        configs = CdnConfiguration.all.index_by(&:provider)

        # We send back the config, but we DO NOT send back the raw secrets
        # unless explicitly necessary, or we mask them for the UI.
        render json: {
          fastly: format_config(configs["fastly"]),
          cloudflare: format_config(configs["cloudflare"]),
          akamai: format_config(configs["akamai"]),
        }
      end

      def update
        provider = params[:provider]
        config = CdnConfiguration.find_or_initialize_by(provider: provider)

        config.is_active = params[:is_active]
        clean_settings = params[:settings].reject do |key, value|
          value.to_s.include?("••••") # Drop masked secrets so they aren't overwritten
        end
        config.settings = (config.settings || {}).merge(clean_settings)

        if config.save
          render json: { success: true, message: "#{provider.titleize} configuration updated." }, status: :ok
        else
          render json: { errors: config.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def format_config(config)
        return { is_active: false, settings: {} } unless config

        # Mask secrets for the UI: show only the last 4 characters
        masked_settings = config.settings.transform_values do |val|
          val.present? ? "••••••••#{val.to_s[-4..-1]}" : ""
        end

        {
          is_active: config.is_active,
          settings: masked_settings,
        }
      end
    end
  end
end
