# frozen_string_literal: true

module Api
  module V1
    class SearchController < ApplicationController
      include AssetUrlHelper
      before_action :authenticate_hybrid!

      RESERVED_PARAMS = %w[q mode schema_id mime_group modified_within file_size_group
                           publish_status approved_status orientation style
                           video_height_min video_height_max video_width_min video_width_max
                           video_format video_codec video_bitrate_min video_bitrate_max
                           audio_codec audio_bitrate_min audio_bitrate_max
                           page per_page sort_by sort_dir controller action format].freeze

      # Field types whose values are suitable for chip/filter UI (bounded option sets)
      FILTERABLE_FIELD_TYPES = %w[select radio tag checkbox].freeze

      # Any schema field type that cannot meaningfully be shown as filter chips
      NON_FILTERABLE_FIELD_TYPES = %w[textarea date datetime boolean number].freeze

      # System/internal property keys excluded from auto-discovery
      SYSTEM_PROPERTY_KEYS = %w[
        size file_size processed_at storage_path checksum_sha256
        original_filename size_human width height depth
        video_height video_width video_bitrate audio_bitrate
        applied_schema_id applied_schema_slug
        content_type color_mode alt_text usage_terms description
        tags image_data thumbnail_data
      ].freeze

      MAX_METADATA_FACET_VALUES  = 20
      MAX_METADATA_CARDINALITY   = 30

      MIME_GROUPS = {
        "images" => [ "image/%" ],
        "documents" => [ "application/pdf", "application/msword",
                        "application/vnd.openxmlformats%", "application/vnd.ms-%",
                        "text/%" ],
        "multimedia" => [ "video/%", "audio/%" ],
        "archives" => [ "application/zip", "application/x-tar",
                       "application/x-rar%", "application/x-7z%",
                       "application/gzip" ],
        "other" => nil,
      }.freeze

      VIDEO_FORMATS = %w[dvi flash mpeg4 mpeg ogg quicktime wmv].freeze
      VIDEO_CODECS = %w[x264 h264 h265 vp9].freeze
      AUDIO_CODECS = %w[libvorbis lame_mp3 aac].freeze
      PUBLISHED_STATUSES = %w[ready approved].freeze

      # Modes that delegate to the pgvector semantic pipeline (AI Gateway embedding
      # + HNSW nearest-neighbour search) instead of the lexical ILIKE pipeline.
      SEMANTIC_MODES = %w[visual agentic].freeze

      INDEX_CACHE_TTL       = 30
      SUGGESTIONS_CACHE_TTL = 15
      SEMANTIC_POOL_LIMIT   = 100
      SUGGESTIONS_ASSET_LIMIT  = 5
      SUGGESTIONS_FOLDER_LIMIT = 3

      # GET /api/v1/search
      #
      # Redis-cached (see {SearchCache}) so repeated queries — very common while
      # a user is refining filters — hit sub-millisecond response times instead
      # of re-running the full ILIKE/facet pipeline every keystroke.
      def index
        payload = SearchCache.fetch(cache_key_for("index"), expires_in: INDEX_CACHE_TTL) { build_index_payload }
        render json: payload
      end

      # GET /api/v1/search/suggestions
      #
      # Lightweight autocomplete used by the global top-bar search box. Returns
      # a small, mixed list of matching assets + folders so the user can jump
      # straight to the asset viewer / folder without a full page load.
      def suggestions
        query = params[:q].to_s.strip
        if query.blank?
          render json: { query: "", results: [] }
          return
        end

        payload = SearchCache.fetch(cache_key_for("suggestions"), expires_in: SUGGESTIONS_CACHE_TTL) do
          build_suggestions_payload(query)
        end
        render json: payload
      end

      private

      # Dispatches to the correct pipeline based on `mode`:
      # * `folders`           → {#build_folder_payload} (Folder model, not Asset)
      # * `visual`/`agentic`  → {#build_semantic_payload} (pgvector similarity)
      # * anything else       → {#build_lexical_payload} (ILIKE + facets, existing behaviour)
      def build_index_payload
        return build_folder_payload if params[:mode] == "folders"
        return build_semantic_payload if SEMANTIC_MODES.include?(params[:mode]) && params[:q].present?

        build_lexical_payload
      end

      def build_lexical_payload
        scope = Asset.active
        scope = apply_text_search(scope)
        scope = apply_mode_filter(scope)
        scope = apply_schema_filter(scope)
        scope = apply_mime_group(scope)
        scope = apply_modified_within(scope)
        scope = apply_file_size_group(scope)
        scope = apply_publish_status(scope)
        scope = apply_approved_status(scope)
        scope = apply_orientation(scope)
        scope = apply_style(scope)
        scope = apply_video_filters(scope)
        scope = apply_audio_filters(scope)
        scope = apply_dynamic_filters(scope)
        scope = apply_sort(scope)

        total = scope.count
        page, per_page, offset, total_pages = pagination_window(total)

        assets = scope.includes(:active_version).offset(offset).limit(per_page)
        facets = build_facets(scope)

        {
          meta: {
            query: params[:q],
            mode: params[:mode] || "all",
            result_type: "asset",
            total_found: total,
            page: page,
            per_page: per_page,
            total_pages: total_pages,
            facets: facets,
          },
          results: assets.map { |asset| format_asset(asset) },
        }
      end

      # Searches {Folder} records by name (folders have no `properties` JSONB
      # column / facets, so this pipeline is intentionally simpler).
      def build_folder_payload
        scope = Folder.active
        scope = scope.where("name ILIKE :q", q: "%#{params[:q]}%") if params[:q].present?
        scope = scope.order(name: :asc)

        total = scope.count
        page, per_page, offset, total_pages = pagination_window(total)
        folders = scope.offset(offset).limit(per_page)

        {
          meta: {
            query: params[:q],
            mode: "folders",
            result_type: "folder",
            total_found: total,
            page: page,
            per_page: per_page,
            total_pages: total_pages,
            facets: {},
          },
          results: folders.map { |folder| format_folder(folder) },
        }
      end

      # Semantic ("Visual Match" / "Ask AI Agent") pipeline: embeds the query via
      # the AI Gateway then runs a pgvector HNSW nearest-neighbour search. Falls
      # back to the lexical pipeline (flagged via `semantic_fallback`) whenever
      # the AI Gateway is unreachable so the search bar never hard-fails.
      def build_semantic_payload
        vector = fetch_query_embedding(params[:q])
        raise "AI Gateway returned no embedding vector" if vector.blank?

        pool = Asset.active.nearest_to_vector(vector).includes(:active_version).limit(SEMANTIC_POOL_LIMIT).to_a
        page, per_page, offset, total_pages = pagination_window(pool.size)
        page_assets = pool[offset, per_page] || []

        {
          meta: {
            query: params[:q],
            mode: params[:mode],
            result_type: "semantic",
            total_found: pool.size,
            page: page,
            per_page: per_page,
            total_pages: total_pages,
            facets: {},
          },
          results: page_assets.map { |asset| format_asset(asset).merge(similarity_score: semantic_score(asset)) },
        }
      rescue StandardError => e
        Rails.logger.warn("[SearchController] semantic search fallback (#{e.class}): #{e.message}")
        build_lexical_payload.tap { |payload| payload[:meta][:semantic_fallback] = true }
      end

      def semantic_score(asset)
        return nil unless asset.respond_to?(:neighbor_distance) && asset.neighbor_distance

        (1.0 - asset.neighbor_distance).round(4)
      end

      # Mixed asset + folder suggestions used by the top-bar autocomplete.
      def build_suggestions_payload(query)
        assets = Asset.active
          .where("title ILIKE :q OR properties->>'original_filename' ILIKE :q", q: "#{query}%")
          .order(updated_at: :desc)
          .limit(SUGGESTIONS_ASSET_LIMIT)

        folders = Folder.active
          .where("name ILIKE :q", q: "#{query}%")
          .order(:name)
          .limit(SUGGESTIONS_FOLDER_LIMIT)

        {
          query: query,
          results: assets.map { |asset| suggestion_for_asset(asset) } +
                   folders.map { |folder| suggestion_for_folder(folder) },
        }
      end

      def suggestion_for_asset(asset)
        props = asset.properties || {}
        {
          type: "asset",
          id: asset.uuid || asset.id,
          title: asset.title || "Untitled Asset",
          subtitle: props["content_type"],
          thumb_url: asset_preview_url_for(asset),
          href: "/assets?id=#{asset.uuid || asset.id}",
        }
      end

      def suggestion_for_folder(folder)
        {
          type: "folder",
          id: folder.id,
          title: folder.name,
          subtitle: "folder",
          href: "/folders?folder=#{folder.id}",
        }
      end

      def format_folder(folder)
        {
          id: folder.id,
          uuid: folder.respond_to?(:uuid) ? folder.uuid : nil,
          title: folder.name,
          type: "folder",
          content_type: "folder",
          href: "/folders?folder=#{folder.id}",
          created_at: folder.created_at&.iso8601,
          updated_at: folder.updated_at&.iso8601,
        }
      end

      def pagination_window(total)
        page = [ params[:page].to_i, 1 ].max
        per_page = params[:per_page].present? ? params[:per_page].to_i : 10
        per_page = [ [ per_page, 1 ].max, 100 ].min
        offset = (page - 1) * per_page
        total_pages = total.zero? ? 0 : (total.to_f / per_page).ceil
        [ page, per_page, offset, total_pages ]
      end

      # Deterministic cache key derived from every incoming query param so
      # distinct filter/sort/page combinations never collide in Redis.
      def cache_key_for(action_name)
        normalized = request.query_parameters.sort.to_h.to_query
        "#{action_name}:#{Digest::SHA256.hexdigest(normalized)}"
      end

      def fetch_query_embedding(text)
        response = gateway_client.post("/api/embed_query", { text: text })
        raise "AI Gateway Error: #{response.status}" unless response.success?

        response.body["vector"]
      end

      def gateway_client
        @gateway_client ||= Faraday.new(url: ai_gateway_url) do |conn|
          conn.request  :json
          conn.response :json
          conn.options.timeout      = 30
          conn.options.open_timeout = 5
          conn.adapter Faraday.default_adapter
        end
      end

      def ai_gateway_url
        Rails.application.credentials.dig(:ai_gateway, :url).presence ||
          ENV.fetch("AI_GATEWAY_URL", "http://localhost:8000")
      end

      def apply_text_search(scope)
        return scope if params[:q].blank?

        scope.where(
          "title ILIKE :q OR properties->>'original_filename' ILIKE :q OR properties::text ILIKE :q",
          q: "%#{params[:q]}%"
        )
      end

      def apply_mode_filter(scope)
        case params[:mode]
        when "images"
          scope.where("properties->>'content_type' ILIKE 'image/%'")
        when "files"
          scope.where.not("properties->>'content_type' ILIKE 'image/%'")
        when "videos"
          scope.where("properties->>'content_type' ILIKE 'video/%'")
        when "documents"
          scope.where("properties->>'content_type' ILIKE 'application/%' OR properties->>'content_type' ILIKE 'text/%'")
        else
          scope
        end
      end

      def apply_schema_filter(scope)
        return scope if params[:schema_id].blank?

        scope.where("(properties->>'applied_schema_id')::int = ?", params[:schema_id].to_i)
      end

      def apply_mime_group(scope)
        group = params[:mime_group]
        return scope if group.blank?

        case group
        when "images", "documents", "multimedia", "archives"
          patterns = MIME_GROUPS[group]
          conditions = patterns.map { "properties->>'content_type' ILIKE ?" }.join(" OR ")
          scope.where(conditions, *patterns)
        when "other"
          all_known = MIME_GROUPS.values.flatten.compact
          conditions = all_known.map { "properties->>'content_type' ILIKE ?" }.join(" OR ")
          scope.where.not(conditions, *all_known)
        else
          scope
        end
      end

      def apply_modified_within(scope)
        modified_after = case params[:modified_within]
        when "hour" then 1.hour.ago
        when "day" then 1.day.ago
        when "week" then 1.week.ago
        when "month" then 1.month.ago
        when "year" then 1.year.ago
        end
        return scope unless modified_after

        scope.where("assets.updated_at >= ?", modified_after)
      end

      def apply_file_size_group(scope)
        case params[:file_size_group]
        when "small"
          scope.where("(properties->>'file_size')::bigint < ?", 1.megabyte)
        when "medium"
          scope.where("(properties->>'file_size')::bigint >= ? AND (properties->>'file_size')::bigint < ?",
                      1.megabyte, 10.megabytes)
        when "large"
          scope.where("(properties->>'file_size')::bigint >= ?", 10.megabytes)
        else
          scope
        end
      end

      def apply_publish_status(scope)
        case params[:publish_status]
        when "published"
          scope.where(status: PUBLISHED_STATUSES)
        when "unpublished"
          scope.where.not(status: PUBLISHED_STATUSES)
        else
          scope
        end
      end

      def apply_approved_status(scope)
        case params[:approved_status]
        when "approved"
          scope.where(status: :approved)
        when "rejected"
          scope.where(status: :rejected)
        else
          scope
        end
      end

      def apply_orientation(scope)
        case params[:orientation]
        when "horizontal"
          scope.where(
            "(properties->>'width')::int > (properties->>'height')::int "             "AND properties->>'width' IS NOT NULL AND properties->>'height' IS NOT NULL"
          )
        when "vertical"
          scope.where(
            "(properties->>'width')::int < (properties->>'height')::int "             "AND properties->>'width' IS NOT NULL AND properties->>'height' IS NOT NULL"
          )
        when "square"
          scope.where(
            "(properties->>'width')::int = (properties->>'height')::int "             "AND properties->>'width' IS NOT NULL AND properties->>'height' IS NOT NULL"
          )
        else
          scope
        end
      end

      def apply_style(scope)
        case params[:style]
        when "black_white"
          scope.where("properties->>'color_mode' IN ('grayscale', 'black_white', 'bw')")
        when "color"
          scope.where(
            "properties->>'color_mode' NOT IN ('grayscale', 'black_white', 'bw') "             "OR properties->>'color_mode' IS NULL"
          )
        else
          scope
        end
      end

      def apply_video_filters(scope)
        if params[:video_height_min].present?
          scope = scope.where("(properties->>'video_height')::int >= ?", params[:video_height_min].to_i)
        end
        if params[:video_height_max].present?
          scope = scope.where("(properties->>'video_height')::int <= ?", params[:video_height_max].to_i)
        end
        if params[:video_width_min].present?
          scope = scope.where("(properties->>'video_width')::int >= ?", params[:video_width_min].to_i)
        end
        if params[:video_width_max].present?
          scope = scope.where("(properties->>'video_width')::int <= ?", params[:video_width_max].to_i)
        end
        if params[:video_format].present?
          scope = scope.where("properties->>'video_format' ILIKE ?", params[:video_format])
        end
        if params[:video_codec].present?
          scope = scope.where("properties->>'video_codec' ILIKE ?", params[:video_codec])
        end
        if params[:video_bitrate_min].present?
          scope = scope.where("(properties->>'video_bitrate')::int >= ?", params[:video_bitrate_min].to_i)
        end
        if params[:video_bitrate_max].present?
          scope = scope.where("(properties->>'video_bitrate')::int <= ?", params[:video_bitrate_max].to_i)
        end
        scope
      end

      def apply_audio_filters(scope)
        if params[:audio_codec].present?
          scope = scope.where("properties->>'audio_codec' ILIKE ?", params[:audio_codec])
        end
        if params[:audio_bitrate_min].present?
          scope = scope.where("(properties->>'audio_bitrate')::int >= ?", params[:audio_bitrate_min].to_i)
        end
        if params[:audio_bitrate_max].present?
          scope = scope.where("(properties->>'audio_bitrate')::int <= ?", params[:audio_bitrate_max].to_i)
        end
        scope
      end

      # Applies any extra query params as JSONB property filters.
      # Supports one-level nested paths via dot notation: editor_state.filter
      # Uses ? placeholders to prevent SQL injection.
      def apply_dynamic_filters(scope)
        filter_params = request.query_parameters.except(*RESERVED_PARAMS)
        filter_params.each do |key, value|
          next unless key.match?(/\A[\w:\-\.]+\z/)
          values_array = value.split(",").map(&:strip).reject(&:blank?)
          next if values_array.empty?

          if key.include?(".") && !key.start_with?(".")
            # Nested: editor_state.filter → properties->'editor_state'->>'filter'
            parent, child = key.split(".", 2)
            next unless parent.match?(/\A[\w:\-]+\z/) && child.match?(/\A[\w:\-]+\z/)
            scope = scope.where("properties->?->>? IN (?)", parent, child, values_array)
          else
            scope = scope.where("properties->>? IN (?)", key, values_array)
          end
        end
        scope
      end

      def apply_sort(scope)
        dir = params[:sort_dir]&.downcase == "asc" ? "ASC" : "DESC"
        case params[:sort_by]
        when "name"
          scope.order(Arel.sql("title #{dir}"))
        when "size"
          scope.order(Arel.sql("(properties->>'file_size')::bigint #{dir} NULLS LAST"))
        when "modified"
          scope.order(Arel.sql("assets.updated_at #{dir}"))
        when "created"
          scope.order(Arel.sql("assets.created_at #{dir}"))
        else
          scope.order(created_at: :desc)
        end
      end

      def build_facets(scope)
        facet_scope = scope.except(:order)

        {
          content_type: facet_scope.pluck(Arel.sql("properties->>'content_type'")).compact.uniq.sort,
          applied_schema: facet_scope.pluck(Arel.sql("properties->>'applied_schema_name'")).compact.uniq.sort,
          mime_group: count_mime_groups(facet_scope),
          status: count_statuses(facet_scope),
          metadata_fields: build_metadata_facets(facet_scope),
        }
      end

      def count_mime_groups(scope)
        ct_list = scope.pluck(Arel.sql("properties->>'content_type'")).compact
        {
          images: ct_list.count { |content_type| content_type.start_with?("image/") },
          documents: ct_list.count { |content_type| content_type.match?(/\A(application\/(pdf|msword|vnd\.)|(text\/))/) },
          multimedia: ct_list.count { |content_type| content_type.start_with?("video/", "audio/") },
          archives: ct_list.count { |content_type| content_type.match?(/\A(application\/(zip|x-tar|x-rar|x-7z|gzip))/) },
        }
      end

      def count_statuses(scope)
        scope.group(:status).count.each_with_object({}) do |(status, count), result|
          key = normalize_status(status)
          result[key] = result.fetch(key, 0) + count
        end
      end

      # Two-phase metadata facet discovery:
      #   Phase 1 — schema-driven: walks active MetadataSchema definitions;
      #             includes any filterable field type with low cardinality.
      #   Phase 2 — property discovery: scans actual property keys from assets
      #             in the result set (catches system fields like applied_schema_name
      #             even when formal metadata has never been entered).
      # Schema-defined entries take precedence so proper labels are shown.
      def build_metadata_facets(scope)
        schema_facets    = build_schema_driven_facets(scope)
        discovered       = build_discovered_facets(scope, skip_keys: schema_facets.keys)
        discovered.merge(schema_facets)
      end

      def build_schema_driven_facets(scope)
        field_defs = {}

        MetadataSchema.active.each do |schema|
          schema.resolved_tabs.each do |tab|
            (tab["fields"] || []).each do |field|
              next if NON_FILTERABLE_FIELD_TYPES.include?(field["field_type"])
              prop_key = field["map_to_property"].presence
              next unless prop_key&.match?(/\A[\w:\-\.]+\z/)

              field_defs[prop_key] ||= field["label"].presence || prop_key
            end
          end
        end

        field_defs.each_with_object({}) do |(prop_key, label), result|
          tally = query_property_tally(scope, prop_key)
          next if tally.empty? || tally.size > MAX_METADATA_CARDINALITY

          result[prop_key] = { label: label, values: format_facet_values(tally) }
        end
      end

      def build_discovered_facets(scope, skip_keys: [])
        # Collect property keys that actually appear in the result set
        asset_ids = scope.limit(500).pluck(:id)
        return {} if asset_ids.empty?

        top_keys = Asset
          .where(id: asset_ids)
          .where.not(properties: {})
          .pluck(Arel.sql("DISTINCT jsonb_object_keys(properties)"))
          .reject { |k| SYSTEM_PROPERTY_KEYS.include?(k) }
          .reject { |k| skip_keys.include?(k) }
          .select { |k| k.match?(/\A[\w:\-\.]+\z/) }

        result = {}

        top_keys.each do |key|
          quoted = ActiveRecord::Base.connection.quote(key)

          # Detect whether this property holds a JSON object or a scalar
          value_type = Asset.where(id: asset_ids)
            .where("jsonb_typeof(properties->#{quoted}) IS NOT NULL")
            .limit(1)
            .pluck(Arel.sql("jsonb_typeof(properties->#{quoted})"))
            .first

          if value_type == "object"
            # Drill one level into the nested object — extract filterable leaf fields
            sub_keys = Asset.where(id: asset_ids)
              .where("jsonb_typeof(properties->#{quoted}) = 'object'")
              .pluck(Arel.sql("DISTINCT jsonb_object_keys(properties->#{quoted})"))
              .select { |k| k.match?(/\A[\w\-]+\z/) }

            sub_keys.each do |sub_key|
              # Only explore scalar-valued sub-keys (skip nested objects like geometry)
              sub_quoted = ActiveRecord::Base.connection.quote(sub_key)
              leaf_type = Asset.where(id: asset_ids)
                .where("jsonb_typeof(properties->#{quoted}->#{sub_quoted}) IS NOT NULL")
                .limit(1)
                .pluck(Arel.sql("jsonb_typeof(properties->#{quoted}->#{sub_quoted})"))
                .first

              next unless %w[string number].include?(leaf_type)

              tally = scope
                .pluck(Arel.sql("properties->#{quoted}->>#{sub_quoted}"))
                .compact.flat_map { |v| v.include?(",") ? v.split(",").map(&:strip) : [ v ] }
                .reject(&:blank?).tally

              # Require at least 1 value (even single-value is useful for nested fields)
              next if tally.empty? || tally.size > MAX_METADATA_CARDINALITY

              composite_key = "#{key}.#{sub_key}"
              label = humanize_property_key("#{key}_#{sub_key}")
              result[composite_key] = { label: label, values: format_facet_values(tally) }
            end
          else
            # Scalar top-level property
            tally = query_property_tally(scope, key)
            next if tally.empty? || tally.size > MAX_METADATA_CARDINALITY || tally.size < 2

            result[key] = { label: humanize_property_key(key), values: format_facet_values(tally) }
          end
        end

        result
      end

      # Returns a tally hash { value => count } for a given property key.
      def query_property_tally(scope, prop_key)
        quoted = ActiveRecord::Base.connection.quote(prop_key)
        scope
          .pluck(Arel.sql("properties->>#{quoted}"))
          .compact
          .flat_map { |v| v.include?(",") ? v.split(",").map(&:strip) : [ v ] }
          .reject(&:blank?)
          .tally
      end

      def format_facet_values(tally)
        tally
          .sort_by { |_, count| -count }
          .first(MAX_METADATA_FACET_VALUES)
          .map { |val, count| { value: val, count: count } }
      end

      # "applied_schema_name"  → "Applied Schema Name"
      # "dc:creator"           → "Creator"
      # "photoshop:City"       → "City"
      # "editor_state_filter"  → "Editor State Filter"
      def humanize_property_key(key)
        field = key.include?(":") ? key.split(":", 2).last : key
        field.gsub(/([A-Z])/, ' \1').strip.split(/[_\s]+/).map(&:capitalize).join(" ")
      end

      def format_asset(asset)
        props = asset.properties || {}
        {
          id: asset.uuid || asset.id,
          uuid: asset.uuid,
          title: asset.title || "Untitled Asset",
          content_type: props["content_type"] || "Unknown",
          size: props["size_human"] || "0 KB",
          file_size: props["file_size"].to_i,
          # `thumb_url`/`preview_url` point at the generated flattened-PNG preview
          # (falls back to the raw file when no preview exists) so formats a
          # browser can't decode natively — PSD, TIFF, HEIC, RAW, PDF, AI, EPS —
          # still render a visual thumbnail instead of a broken <img>. `url`
          # keeps the raw/original asset URL for download/full-quality use.
          thumb_url: asset_preview_url_for(asset),
          preview_url: asset_preview_url_for(asset),
          url: asset_url_for(asset),
          web_renderable: web_renderable_image?(props["content_type"]),
          folder_id: asset.folder_id,
          status: normalize_status(asset.read_attribute_before_type_cast(:status)),
          width: props["width"]&.to_i,
          height: props["height"]&.to_i,
          created_at: asset.created_at&.iso8601,
          updated_at: asset.updated_at&.iso8601,
          schema_name: props["applied_schema_name"],
          schema_id: props["applied_schema_id"],
          metadata: {
            creator: props["dc:creator"],
            description: props["dc:description"],
            sku: props["dam:sku"],
            brand: props["dam:brand"],
            asset_type: props["dam:asset_type"],
            product_id: props["dam:product_id"],
            language: props["dam:language_code"],
            tags: props["tags"],
          }.compact,
        }
      end

      # Whether +content_type+ is a MIME type a browser can decode natively in
      # an +<img>+ tag. Mirrors Api::V1::AssetsController#web_renderable_image?
      # so search results/suggestions can flag when +thumb_url+ points at a
      # generated preview rather than the original file.
      #
      # @param content_type [String, nil]
      # @return [Boolean]
      def web_renderable_image?(content_type)
        AssetProcessorWorker::WEB_RENDERABLE_MIME_TYPES.include?(content_type.to_s)
      end

      def normalize_status(status)
        raw = status.to_s
        key = if Asset.statuses.key?(raw)
          raw
        else
          Asset.statuses.key(raw.to_i) || raw
        end
        key == "ready" ? "active" : key
      end
    end
  end
end
