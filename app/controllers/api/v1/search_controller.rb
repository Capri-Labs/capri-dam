module Api
  module V1
    class SearchController < ApplicationController
      include AssetUrlHelper
      before_action :authenticate_hybrid!

      def index
        query = params[:q]
        mode  = params[:mode] || "images"

        assets_scope = Asset.active

        # 1. Full-text lexical search — title, filename, AND all JSONB metadata fields
        if query.present?
          # Searches title, filename, and any value inside the properties JSONB column
          assets_scope = assets_scope.where(
            "title ILIKE :q " \
            "OR properties->>'original_filename' ILIKE :q " \
            "OR properties::text ILIKE :q",
            q: "%#{query}%"
          )
        end

        # 2. Mode Filtering
        case mode
        when "images"
          assets_scope = assets_scope.where("properties->>'content_type' ILIKE 'image/%'")
        when "files"
          assets_scope = assets_scope.where.not("properties->>'content_type' ILIKE 'image/%'")
        end

        # 3. Schema metadata filtering
        # Allow ?schema_id=123 to restrict results to assets using that schema
        if params[:schema_id].present?
          assets_scope = assets_scope.where("(properties->>'applied_schema_id')::int = ?", params[:schema_id].to_i)
        end

        # 4. DYNAMIC METADATA FILTERING
        # Any non-standard param is treated as a JSONB property filter
        reserved_params = %w[q mode schema_id controller action format]
        filter_params   = request.query_parameters.except(*reserved_params)

        filter_params.each do |key, value|
          values_array = value.split(",")
          assets_scope = assets_scope.where(
            "properties->>:key IN (:values)",
            key: key, values: values_array
          )
        end

        # 5. FACET GENERATION
        facets = {
          content_type:  assets_scope.pluck(Arel.sql("properties->>'content_type'")).compact.uniq,
          applied_schema: assets_scope.pluck(
            Arel.sql("properties->>'applied_schema_name'")
          ).compact.uniq.sort,
        }

        results = assets_scope.includes(:active_version).limit(100).map do |asset|
          {
            id:            asset.uuid || asset.id,
            uuid:          asset.uuid,
            title:         asset.title || "Untitled Asset",
            type:          asset.properties&.dig("content_type") || "Unknown",
            size:          asset.properties&.dig("size_human") || "0 KB",
            thumb_url:     asset_url_for(asset),
            folder_id:     asset.folder_id,
            # Surface the schema-applied metadata so search results can show enriched data
            schema_name:   asset.properties&.dig("applied_schema_name"),
            schema_id:     asset.properties&.dig("applied_schema_id"),
            # Key metadata fields for preview in search results
            metadata: {
              creator:     asset.properties&.dig("dc:creator"),
              title_meta:  asset.properties&.dig("dc:title"),
              description: asset.properties&.dig("dc:description"),
              sku:         asset.properties&.dig("dam:sku"),
              brand:       asset.properties&.dig("dam:brand"),
              asset_type:  asset.properties&.dig("dam:asset_type"),
              product_id:  asset.properties&.dig("dam:product_id"),
              language:    asset.properties&.dig("dam:language_code"),
              tags:        asset.properties&.dig("tags"),
            }.compact,
          }
        end

        render json: {
          meta: {
            query:       query,
            mode:        mode,
            total_found: assets_scope.count,
            facets:      facets,
          },
          results: results,
        }
      end
    end
  end
end
