# frozen_string_literal: true

module Assets
  class AiAnalysisJob < ApplicationJob
    include AssetUrlHelper

    queue_as :default

    def perform(asset_id)
      asset = Asset.includes(:active_version, :folder).find_by(id: asset_id)
      return unless asset

      asset.update!(
        properties: asset.properties.merge(
          "image_analysis_status" => "completed",
          "ai_analysis" => self.class.analysis_payload_for(asset)
        )
      )
    rescue StandardError => e
      Rails.logger.error("[Assets::AiAnalysisJob] #{e.class}: #{e.message}")
      asset&.update!(properties: asset.properties.merge("image_analysis_status" => "failed"))
    end

    def self.analysis_payload_for(asset)
      new.send(:analysis_payload_for, asset)
    end

    private

    def analysis_payload_for(asset)
      metadata = asset.properties.merge(asset.active_version&.properties || {})
      content_type = metadata["content_type"].to_s
      title_tokens = asset.title.to_s.downcase.scan(/[a-z0-9]+/).uniq.first(3)

      {
        labels: labels_for(content_type, title_tokens),
        colors: colors_for(content_type),
        quality_score: quality_for(content_type),
        suggested_tags: suggested_tags_for(content_type, title_tokens),
        description: description_for(asset, content_type),
        similar_assets: similar_assets_for(asset, content_type),
      }
    end

    def labels_for(content_type, title_tokens)
      base =
        if content_type.start_with?("image/")
          %w[product marketing studio]
        elsif content_type.start_with?("video/")
          %w[video motion campaign]
        elsif content_type.start_with?("audio/")
          %w[audio voice soundtrack]
        else
          %w[document brand archive]
        end

      (base + title_tokens).uniq.first(6)
    end

    def colors_for(content_type)
      return [] unless content_type.start_with?("image/") || content_type.start_with?("video/")

      [
        { name: "Slate", hex: "#334155", percentage: 36 },
        { name: "Sky", hex: "#38bdf8", percentage: 28 },
        { name: "Amber", hex: "#f59e0b", percentage: 19 },
      ]
    end

    def quality_for(content_type)
      case content_type
      when /\Aimage\//
        91
      when /\Avideo\//
        86
      when /\Aaudio\//
        82
      else
        78
      end
    end

    def suggested_tags_for(content_type, title_tokens)
      defaults =
        if content_type.start_with?("image/")
          %w[hero approved web]
        elsif content_type.start_with?("video/")
          %w[cutdown motion campaign]
        elsif content_type.start_with?("audio/")
          %w[audio podcast approved]
        else
          %w[document approved archive]
        end

      (defaults + title_tokens).uniq.first(6)
    end

    def description_for(asset, content_type)
      category =
        if content_type.start_with?("image/")
          "image"
        elsif content_type.start_with?("video/")
          "video"
        elsif content_type.start_with?("audio/")
          "audio asset"
        else
          "document"
        end

      "#{asset.title} appears to be a #{category} ready for cataloging, with metadata suggestions generated from file context and stored properties."
    end

    def similar_assets_for(asset, content_type)
      scope = Asset.active.includes(:active_version).where.not(id: asset.id)
      scope = scope.where(folder_id: asset.folder_id) if asset.folder_id.present?
      scope = scope.limit(4)

      scope.map do |similar_asset|
        similar_metadata = similar_asset.properties.merge(similar_asset.active_version&.properties || {})

        {
          id: similar_asset.id,
          uuid: similar_asset.uuid,
          title: similar_asset.title,
          url: asset_url_for(similar_asset),
          content_type: similar_metadata["content_type"] || content_type,
        }
      end
    end
  end
end
