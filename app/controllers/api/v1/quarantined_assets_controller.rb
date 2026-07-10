module Api
  module V1
    class QuarantinedAssetsController < ApplicationController
      include AssetUrlHelper

      # Only skip CSRF when the caller authenticates with a bearer token (see
      # ApplicationController#token_authenticated_request?); cookie-session
      # requests still require a valid CSRF token.
      protect_from_forgery with: :null_session, if: -> { token_authenticated_request? }

      before_action :authenticate_hybrid!
      before_action :require_admin!
      before_action :require_admin_scope!, only: %i[release discard]
      before_action :set_quarantined_asset, only: %i[show release discard]

      VALID_STATUSES = %w[all pending_review resolved discarded].freeze

      def index
        page = [ params[:page].to_i, 1 ].max
        per_page = (params[:per_page].presence || 25).to_i.clamp(1, 100)
        scope = status_scope

        total = scope.count
        entries = scope.includes(:system_connector, :asset, :reviewed_by)
                       .order(created_at: :desc)
                       .offset((page - 1) * per_page)
                       .limit(per_page)

        render json: {
          items: entries.map { |entry| serialize_entry(entry, include_payload: false) },
          pagination: {
            total: total,
            page: page,
            per_page: per_page,
            pages: (total.to_f / per_page).ceil,
          },
        }
      end

      def show
        render json: { entry: serialize_entry(@quarantined_asset, include_payload: true) }
      end

      def release
        @quarantined_asset.release!(reviewer: current_user, notes: review_notes_param)

        render json: {
          entry: serialize_entry(@quarantined_asset.reload, include_payload: true),
          message: "Quarantined asset released.",
        }
      rescue StandardError => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      def discard
        @quarantined_asset.discard!(reviewer: current_user, notes: review_notes_param)

        render json: {
          entry: serialize_entry(@quarantined_asset.reload, include_payload: true),
          message: "Quarantined asset discarded.",
        }
      rescue StandardError => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      def stats
        render json: {
          pending_review: QuarantinedAsset.pending_review.count,
          resolved: QuarantinedAsset.resolved.count,
          discarded: QuarantinedAsset.discarded.count,
          total: QuarantinedAsset.count,
        }
      end

      private

      def set_quarantined_asset
        @quarantined_asset = QuarantinedAsset.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Quarantined asset not found." }, status: :not_found
      end

      def status_scope
        case params[:status].to_s
        when "resolved"
          QuarantinedAsset.resolved
        when "discarded"
          QuarantinedAsset.discarded
        when "all"
          QuarantinedAsset.all
        else
          QuarantinedAsset.pending_review
        end
      end

      def serialize_entry(entry, include_payload:)
        data = {
          id: entry.id,
          status: entry.status,
          rejection_reason: entry.rejection_reason,
          flagged_at: entry.created_at&.iso8601,
          reviewed_at: entry.reviewed_at&.iso8601,
          review_notes: entry.review_notes,
          reviewed_by: entry.reviewed_by&.email,
          system_connector: {
            id: entry.system_connector_id,
            name: entry.system_connector&.name,
          },
          asset: serialize_asset(entry),
        }

        data[:original_payload] = entry.original_payload if include_payload
        data
      end

      def serialize_asset(entry)
        asset = entry.asset
        metadata = (asset&.properties || {}).merge(asset&.active_version&.properties || {})
        uploaded_at = asset&.created_at || entry.payload_uploaded_at || entry.created_at
        uploaded_by = asset&.user&.email || entry.payload_owner&.email

        {
          id: asset&.id,
          uuid: asset&.uuid,
          title: asset&.title || entry.payload_title,
          status: asset&.status,
          trashed: asset&.trashed? || false,
          preview_url: asset.present? ? asset_preview_url_for(asset) : nil,
          url: asset.present? ? asset_url_for(asset) : nil,
          content_type: metadata["content_type"].presence || metadata["mime_type"].presence || entry.payload_content_type,
          uploaded_by: uploaded_by,
          uploaded_at: uploaded_at&.iso8601,
        }
      end

      def review_notes_param
        params[:review_notes].to_s.strip.presence
      end
    end
  end
end
