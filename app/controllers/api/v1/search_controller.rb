module Api
  module V1
    class SearchController < ApplicationController
      before_action :authenticate_user!

      def index
        query = params[:q]
        mode = params[:mode] || 'images'

        assets_scope = Asset.active

        # 1. Lexical Search
        if query.present?
          assets_scope = assets_scope.where(
            "title ILIKE :q OR properties->>'original_filename' ILIKE :q",
            q: "%#{query}%"
          )
        end

        # 2. Mode Filtering
        case mode
        when 'images'
          assets_scope = assets_scope.where("properties->>'content_type' ILIKE 'image/%'")
        when 'files'
          assets_scope = assets_scope.where.not("properties->>'content_type' ILIKE 'image/%'")
        end

        # 3. DYNAMIC METADATA FILTERING (The Magic)
        # We look for any query params that aren't the standard ones, and assume they are JSONB property filters
        reserved_params = ['q', 'mode', 'controller', 'action', 'format']
        filter_params = request.query_parameters.except(*reserved_params)

        filter_params.each do |key, value|
          # Supports comma-separated values (e.g., ?region=EMEA,APAC)
          values_array = value.split(',')
          assets_scope = assets_scope.where("properties->>:key IN (:values)", key: key, values: values_array)
        end

        # 4. FACET GENERATION (For the React UI)
        # In a massive database, you would use Elasticsearch/OpenSearch for this.
        # For Postgres, we can dynamically pluck distinct values from the filtered scope.
        facets = {
          content_type: assets_scope.pluck(Arel.sql("properties->>'content_type'")).compact.uniq,
          # Example of a custom business facet:
          # region: assets_scope.pluck(Arel.sql("properties->>'region'")).compact.uniq
        }

        results = assets_scope.limit(50).map do |asset|
          {
            id: asset.id,
            uuid: asset.uuid,
            title: asset.title || "Untitled Asset",
            type: asset.properties&.dig('content_type') || 'Unknown',
            size: asset.properties&.dig('size_human') || '0 KB',
            thumb_url: asset.properties['storage_path'] ? "https://cdn.yourdam.com/assets/#{asset.uuid}?w=400" : nil
          }
        end

        render json: {
          meta: {
            query: query,
            mode: mode,
            total_found: assets_scope.count,
            facets: facets # Send the available filter options to React
          },
          results: results
        }
      end
    end
  end
end