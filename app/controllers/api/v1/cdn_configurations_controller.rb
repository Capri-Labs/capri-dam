module Api
  module V1
    class CdnConfigurationsController < ApplicationController
      before_action :authenticate_hybrid!
      before_action :require_admin!, only: %i[update]

      # Output formats the Fastly Image Optimizer (Fastly IO) integration can be
      # configured to request. This is a configuration allow-list only — it
      # controls which formats an administrator may opt into; it does not, by
      # itself, perform any live image transformation (see
      # docs/developer-guide/src/19_cdn-edge.adoc for the current scope).
      FASTLY_IMAGE_OPTIMIZER_FORMATS = %w[webp avif].freeze

      # Settings keys that hold plain configuration values (not secrets) and
      # therefore should never be masked in the #index response.
      NON_SECRET_SETTINGS_KEYS = %w[image_optimizer_formats].freeze

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
        raw_settings = params[:settings].respond_to?(:to_unsafe_h) ? params[:settings].to_unsafe_h : params.fetch(:settings, {})
        clean_settings = raw_settings.reject do |key, value|
          value.to_s.include?("••••") # Drop masked secrets so they aren't overwritten
        end

        if clean_settings.key?("image_optimizer_formats")
          formats = Array(clean_settings["image_optimizer_formats"]).map(&:to_s)
          invalid = formats - FASTLY_IMAGE_OPTIMIZER_FORMATS
          if invalid.any?
            render json: {
              errors: [ "Unsupported image optimizer format(s): #{invalid.join(", ")}. Supported: #{FASTLY_IMAGE_OPTIMIZER_FORMATS.join(", ")}." ],
            }, status: :unprocessable_entity
            return
          end
          clean_settings["image_optimizer_formats"] = formats
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

        # Mask secrets for the UI (show only the last 4 characters), but pass
        # plain configuration values (e.g. the image optimizer format
        # allow-list) through untouched — they are not secrets.
        masked_settings = config.settings.each_with_object({}) do |(key, val), acc|
          acc[key] = if NON_SECRET_SETTINGS_KEYS.include?(key.to_s)
            val
          else
            val.present? ? "••••••••#{val.to_s[-4..-1]}" : ""
          end
        end

        {
          is_active: config.is_active,
          settings: masked_settings,
        }
      end
    end
  end
end
