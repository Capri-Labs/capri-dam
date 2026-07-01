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

      def index
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
        page = [ params[:page].to_i, 1 ].max
        per_page = params[:per_page].present? ? params[:per_page].to_i : 10
        per_page = [ [ per_page, 1 ].max, 100 ].min
        offset = (page - 1) * per_page
        total_pages = (total.to_f / per_page).ceil

        assets = scope.includes(:active_version).offset(offset).limit(per_page)
        facets = build_facets(scope)
        results = assets.map { |asset| format_asset(asset) }

        render json: {
          meta: {
            query: params[:q],
            mode: params[:mode] || "all",
            total_found: total,
            page: page,
            per_page: per_page,
            total_pages: total_pages,
            facets: facets,
          },
          results: results,
        }
      end

      private

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

      def apply_dynamic_filters(scope)
        filter_params = request.query_parameters.except(*RESERVED_PARAMS)
        filter_params.each do |key, value|
          values_array = value.split(",")
          scope = scope.where("properties->>:key IN (:values)", key: key, values: values_array)
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

      def format_asset(asset)
        props = asset.properties || {}
        {
          id: asset.uuid || asset.id,
          uuid: asset.uuid,
          title: asset.title || "Untitled Asset",
          content_type: props["content_type"] || "Unknown",
          size: props["size_human"] || "0 KB",
          file_size: props["file_size"].to_i,
          thumb_url: asset_url_for(asset),
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
