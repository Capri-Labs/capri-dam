# frozen_string_literal: true

module Api
  module V1
    # The links between assets and entities, and the resolution pass that
    # proposes them from tags the library already has.
    #
    # THE INVARIANT THIS CONTROLLER PROTECTS
    # --------------------------------------
    # A link created by resolution or by a model is a *proposal* about identity,
    # and identity is what consent and rights decisions later hang on. Only
    # {#create} — a signed-in user with modify rights on the asset — produces an
    # asserted link; everything machine-derived arrives unconfirmed and stays
    # that way until {#confirm}. Without that line, a spelling coincidence could
    # authorise a release.
    #
    # @see AssetEntity
    # @see Entities::Resolver
    class AssetEntitiesController < ApplicationController
      before_action :authenticate_hybrid!
      before_action :set_asset, only: %i[index create resolve]
      before_action :set_link, only: %i[confirm destroy]

      # GET /api/v1/assets/:asset_id/entities
      #
      # @return [void]
      def index
        check_asset_read!(@asset)
        return if performed?

        links = @asset.asset_entities.includes(:entity, :confirmed_by).order(:relationship)

        render json: { asset_id: @asset.id, links: links.map { |link| serialize(link) } }
      end

      # POST /api/v1/assets/:asset_id/entities
      #
      # Creates a human assertion. Source is forced to +manual+ rather than
      # taken from the request: a client that could name its own source could
      # post a machine guess that arrives already indistinguishable from a
      # curator's statement.
      #
      # @return [void]
      def create
        check_asset_modify!(@asset)
        return if performed?

        entity = Entity.find_by(id: params[:entity_id])
        return render json: { error: "Entity not found." }, status: :not_found if entity.nil?

        link = @asset.asset_entities.new(
          entity: entity.canonical_entity,
          relationship: params[:relationship],
          source: "manual",
          created_by: current_user,
          confirmed_at: Time.current,
          confirmed_by: current_user,
        )

        if link.save
          render json: serialize(link), status: :created
        else
          render json: { errors: link.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # POST /api/v1/assets/:asset_id/entities/resolve
      #
      # Reads the asset's tags and proposes links for the ones that name a known
      # entity. Pass +dry_run=true+ to see what it would do without writing.
      #
      # Tags are never modified. They remain the raw record of what somebody
      # typed, so the pass can be re-run after the alias table improves — which
      # is the only way anyone will be willing to run it a second time.
      #
      # @return [void]
      def resolve
        check_asset_modify!(@asset)
        return if performed?

        dry_run = ActiveModel::Type::Boolean.new.cast(params[:dry_run]).present?
        outcome = Entities::Resolver.call(@asset, dry_run: dry_run)

        render json: outcome.to_h.merge(asset_id: @asset.id, dry_run: dry_run)
      end

      # POST /api/v1/asset_entities/:id/confirm
      #
      # @return [void]
      def confirm
        check_asset_modify!(@link.asset)
        return if performed?

        @link.confirm!(user: current_user)
        render json: serialize(@link)
      end

      # DELETE /api/v1/asset_entities/:id
      #
      # @return [void]
      def destroy
        check_asset_modify!(@link.asset)
        return if performed?

        @link.destroy!
        head :no_content
      end

      private

      def set_asset
        @asset = Asset.find_by(id: params[:asset_id]) || Asset.find_by(uuid: params[:asset_id])
        render json: { error: "Asset not found." }, status: :not_found if @asset.nil?
      end

      def set_link
        @link = AssetEntity.find_by(id: params[:id])
        render json: { error: "Link not found." }, status: :not_found if @link.nil?
      end

      def serialize(link)
        {
          id: link.id,
          asset_id: link.asset_id,
          entity: {
            id: link.entity.id,
            name: link.entity.name,
            entity_type: link.entity.entity_type,
            reference: "#{link.entity.entity_type}:#{link.entity.slug}",
          },
          relationship: link.relationship,
          source: link.source,
          confidence: link.confidence,
          # Surfaced explicitly rather than left for the client to infer from
          # source/confirmed_at, so every consumer reads the same rule.
          asserted: link.asserted?,
          confirmed_at: link.confirmed_at,
          confirmed_by: link.confirmed_by&.email,
          created_at: link.created_at,
        }
      end
    end
  end
end
