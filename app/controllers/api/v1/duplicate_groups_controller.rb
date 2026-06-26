# REST API controller for the Duplicate Manager feature.
#
# Exposes {DuplicateGroup} records so the frontend can list, inspect, and
# resolve groups of duplicate assets.
#
# == Endpoint summary
#
# | Method | Path                                      | Action           | Description                                |
# |--------|-------------------------------------------|------------------|--------------------------------------------|
# | GET    | /api/v1/duplicate_groups                  | {#index}         | List pending groups (max 100)              |
# | GET    | /api/v1/duplicate_groups/:id              | {#show}          | Detail + member assets                     |
# | PATCH  | /api/v1/duplicate_groups/:id/resolve      | {#resolve}       | Keep all or soft-delete chosen assets      |
# | PATCH  | /api/v1/duplicate_groups/:id/dismiss      | {#dismiss}       | Hide group without deleting anything       |
# | PATCH  | /api/v1/duplicate_groups/bulk_resolve     | {#bulk_resolve}  | Resolve multiple groups in one call        |
# | GET    | /api/v1/duplicate_groups/stats            | {#stats}         | Group counts per status                    |
#
# == Authentication
#
# All actions require a Devise session or Doorkeeper bearer token.
#
# @see DuplicateGroup
# @see DuplicateDetectionService
module Api
  module V1
    class DuplicateGroupsController < ApplicationController
      include AssetUrlHelper

      before_action :authenticate_hybrid!
      before_action :set_group, only: %i[show resolve dismiss]

      # GET /api/v1/duplicate_groups
      #
      # Optional query params:
      # * +status+ — +"pending"+ (default) | +"resolved"+ | +"dismissed"+ | +"all"+
      #
      # @return [void] JSON +{ total:, groups: [] }+
      def index
        scope = case params[:status]
        when "resolved"  then DuplicateGroup.resolved
        when "dismissed" then DuplicateGroup.dismissed
        when "all"       then DuplicateGroup.all
        else                  DuplicateGroup.for_display
        end

        scope = scope.order(created_at: :desc)
        scope = scope.limit(DuplicateGroup::DISPLAY_LIMIT) unless params[:status] == "all"

        groups = scope.includes(duplicate_group_assets: :asset)

        render json: {
          total:  groups.count,
          groups: groups.map { |g| serialize_group(g, include_assets: false) },
        }
      end

      # GET /api/v1/duplicate_groups/:id
      #
      # @return [void] JSON full group with member assets
      def show
        render json: { group: serialize_group(@group, include_assets: true) }
      end

      # GET /api/v1/duplicate_groups/stats
      #
      # @return [void] JSON +{ pending:, resolved:, dismissed:, total: }+
      def stats
        render json: {
          pending:   DuplicateGroup.pending.count,
          resolved:  DuplicateGroup.resolved.count,
          dismissed: DuplicateGroup.dismissed.count,
          total:     DuplicateGroup.count,
        }
      end

      # PATCH /api/v1/duplicate_groups/:id/resolve
      #
      # Accepted parameters:
      # * +action+           — +"kept_all"+ | +"deleted_duplicates"+
      # * +asset_ids_to_delete+ — Array<String> UUIDs to soft-delete (when action == "deleted_duplicates")
      #
      # @return [void] JSON resolved group or error
      def resolve
        action         = params[:action_type].presence || "kept_all"
        ids_to_delete  = Array(params[:asset_ids_to_delete])

        unless %w[kept_all deleted_duplicates].include?(action)
          return render json: { error: "Invalid action. Use kept_all or deleted_duplicates." },
                        status: :unprocessable_entity
        end

        soft_deleted = []

        if action == "deleted_duplicates" && ids_to_delete.any?
          # Guard: never delete the original.
          original_id = @group.duplicate_group_assets
                               .where(is_original: true)
                               .pick(:asset_id)

          ids_to_delete.each do |asset_uuid|
            next if asset_uuid.to_s == original_id.to_s

            asset = Asset.find_by(id: asset_uuid)
            next unless asset

            asset.update!(deleted_at: Time.current)
            soft_deleted << asset_uuid
          end
        end

        @group.resolve!(action: action, user: current_user)

        render json: {
          group:        serialize_group(@group, include_assets: false),
          deleted_ids:  soft_deleted,
          message:      "Group resolved successfully.",
        }
      rescue StandardError => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # PATCH /api/v1/duplicate_groups/:id/dismiss
      #
      # @return [void] JSON dismissed group
      def dismiss
        @group.dismiss!(user: current_user)
        render json: { group: serialize_group(@group, include_assets: false),
                       message: "Group dismissed." }
      end

      # PATCH /api/v1/duplicate_groups/bulk_resolve
      #
      # Accepted parameters:
      # * +group_ids+ — Array<String> UUIDs of groups to resolve
      # * +action+    — +"kept_all"+ (only kept_all is supported for bulk)
      #
      # @return [void] JSON +{ resolved_count: }+
      def bulk_resolve
        group_ids = Array(params[:group_ids])
        action    = "kept_all"

        groups = DuplicateGroup.pending.where(id: group_ids)
        groups.each { |g| g.resolve!(action: action, user: current_user) }

        render json: {
          resolved_count: groups.count,
          message:        "#{groups.count} group(s) resolved.",
        }
      end

      private

      # @return [void]
      def set_group
        @group = DuplicateGroup.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Duplicate group not found." }, status: :not_found
      end

      # Serialises a {DuplicateGroup} for the API response.
      #
      # @param group          [DuplicateGroup]
      # @param include_assets [Boolean]
      # @return [Hash]
      def serialize_group(group, include_assets:)
        data = {
          id:                group.id,
          checksum:          group.checksum,
          status:            group.status,
          resolution_action: group.resolution_action,
          total_count:       group.total_count,
          resolved_at:       group.resolved_at,
          resolved_by:       group.resolved_by&.email,
          created_at:        group.created_at,
          updated_at:        group.updated_at,
        }

        if include_assets
          data[:assets] = group.duplicate_group_assets
                               .includes(:asset)
                               .order(is_original: :desc, created_at: :asc)
                               .map { |dga| serialize_member(dga) }
        end

        data
      end

      # Serialises a {DuplicateGroupAsset} (member) for the API response.
      #
      # @param dga [DuplicateGroupAsset]
      # @return [Hash]
      def serialize_member(dga)
        asset = dga.asset
        return { asset_id: dga.asset_id, is_original: dga.is_original } unless asset

        version = asset.active_version

        {
          asset_id:       asset.id,
          title:          asset.title,
          is_original:    dga.is_original,
          status:         asset.status,
          url:            asset_url_for(asset),
          folder_id:      asset.folder_id,
          folder_name:    asset.folder&.name || "Root / Uncategorized",
          folder_path:    asset.folder&.path,
          content_type:   version&.properties&.dig("content_type"),
          file_size:      version&.properties&.dig("size"),
          uploaded_at:    asset.created_at&.iso8601,
          uploaded_by:    asset.user&.email,
        }
      end
    end
  end
end
