# frozen_string_literal: true

module Api
  module V1
    # CRUD and merge for typed entities — the people, products, places,
    # campaigns, brands and events the library refers to.
    #
    # WHAT THIS EXISTS TO FIX
    # -----------------------
    # +assets.properties["tags"]+ holds strings, and a string cannot say what it
    # refers to. "Berlin" the city, "Berlin" the photographer and "Berlin" the
    # campaign are one token there. Entities give each of those an identity, so
    # a question spanning them becomes answerable instead of merely plausible.
    #
    # @see Entity
    # @see Entities::Merger
    class EntitiesController < ApplicationController
      before_action :authenticate_hybrid!
      before_action :set_entity, only: %i[show update destroy merge add_alias remove_alias]

      # The picker in the query builder is only as good as its page size, but an
      # unbounded list is a full table scan on a table designed to grow without
      # limit.
      MAX_PAGE_SIZE = 100

      # GET /api/v1/entities/vocabulary
      #
      # The types, the relationships, and — critically — which relationships may
      # point at which types. Served rather than hardcoded in the client for the
      # same reason the search field registry is: a client-side copy eventually
      # offers a combination the server rejects, and the failure looks like a
      # bug in the user's input rather than a stale constant.
      #
      # @return [void]
      def vocabulary
        render json: {
          entity_types: Entity::TYPES,
          relationships: AssetEntity::RELATIONSHIPS.map do |relationship|
            {
              name: relationship,
              label: relationship.humanize,
              entity_types: AssetEntity.types_for(relationship),
            }
          end,
          sources: AssetEntity::SOURCES,
        }
      end

      # GET /api/v1/entities
      #
      # @return [void]
      def index
        scope = Entity.canonical_only
        scope = scope.where(entity_type: params[:entity_type]) if params[:entity_type].present?
        scope = apply_name_search(scope)

        entities = scope.order(:name).limit(page_size).offset(offset)

        render json: {
          entities: entities.map { |entity| serialize(entity) },
          total: scope.count,
        }
      end

      # GET /api/v1/entities/:id
      #
      # @return [void]
      def show
        render json: serialize(@entity, detailed: true)
      end

      # POST /api/v1/entities
      #
      # @return [void]
      def create
        entity = Entity.new(entity_params)
        entity.created_by = current_user

        if entity.save
          apply_aliases(entity, params[:aliases])
          render json: serialize(entity, detailed: true), status: :created
        else
          render json: { errors: entity.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # PATCH /api/v1/entities/:id
      #
      # @return [void]
      def update
        # The type is deliberately not updatable. Changing it would invalidate
        # every existing link in one write — a "shot_by person" would become a
        # "shot_by campaign", which the relationship matrix forbids on creation
        # but cannot retroactively undo. Reclassifying means creating the right
        # entity and merging, which leaves a trail.
        if @entity.update(entity_params.except(:entity_type))
          render json: serialize(@entity, detailed: true)
        else
          render json: { errors: @entity.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/entities/:id
      #
      # Refused while links exist. Deleting would silently strip a claim from
      # every asset that carried it, and the only record that it ever existed is
      # the link being destroyed. Merging is the operation that handles a
      # duplicate; deletion is only for something created by mistake.
      #
      # @return [void]
      def destroy
        link_count = @entity.asset_entities.count

        if link_count.positive?
          return render json: {
            error: "#{link_count} asset(s) still link to this entity. Merge it into another entity instead.",
          }, status: :conflict
        end

        @entity.destroy!
        head :no_content
      end

      # POST /api/v1/entities/:id/merge
      #
      # @return [void]
      def merge
        canonical = Entity.find_by(id: params[:canonical_id])
        return render json: { error: "Target entity not found." }, status: :not_found if canonical.nil?

        result = Entities::Merger.call(duplicate: @entity, canonical: canonical)

        render json: {
          canonical: serialize(result.canonical, detailed: true),
          links_moved: result.links_moved,
          links_discarded: result.links_discarded,
          aliases_moved: result.aliases_moved,
        }
      rescue ArgumentError => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # POST /api/v1/entities/:id/aliases
      #
      # @return [void]
      def add_alias
        record = @entity.entity_aliases.new(alias_text: params[:alias_text], source: "manual")

        if record.save
          render json: serialize(@entity, detailed: true), status: :created
        else
          render json: { errors: record.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/entities/:id/aliases/:alias_id
      #
      # @return [void]
      def remove_alias
        record = @entity.entity_aliases.find_by(id: params[:alias_id])
        return render json: { error: "Alias not found." }, status: :not_found if record.nil?

        record.destroy!
        render json: serialize(@entity, detailed: true)
      end

      private

      def set_entity
        @entity = Entity.find_by(id: params[:id])
        render json: { error: "Entity not found." }, status: :not_found if @entity.nil?
      end

      def entity_params
        params.require(:entity).permit(:entity_type, :name, :slug, :description,
                                       properties: {}, external_ids: {})
      end

      def apply_name_search(scope)
        term = params[:q].to_s.strip
        return scope if term.blank?

        normalised = EntityAlias.normalise(term)

        # Searched against aliases as well as the name, or the picker cannot
        # find the entity by the string the user actually has in mind — which is
        # usually the one that got recorded as an alias in the first place.
        scope.where("lower(entities.name) LIKE ?", "%#{sanitize_sql_like(normalised)}%")
             .or(scope.where(id: EntityAlias.where("alias_text LIKE ?", "%#{sanitize_sql_like(normalised)}%")
                                            .select(:entity_id)))
      end

      def sanitize_sql_like(value)
        ActiveRecord::Base.sanitize_sql_like(value)
      end

      def apply_aliases(entity, values)
        Array(values).each do |value|
          entity.entity_aliases.create(alias_text: value, source: "manual")
        end
      end

      def page_size
        [ params.fetch(:limit, 50).to_i, MAX_PAGE_SIZE ].min.clamp(1, MAX_PAGE_SIZE)
      end

      def offset
        [ params.fetch(:offset, 0).to_i, 0 ].max
      end

      def serialize(entity, detailed: false)
        base = {
          id: entity.id,
          entity_type: entity.entity_type,
          name: entity.name,
          slug: entity.slug,
          # The reference form a search filter takes. Emitted by the server so
          # a client never has to build it — and so the qualified form stays the
          # only form anybody learns.
          reference: "#{entity.entity_type}:#{entity.slug}",
          description: entity.description,
          asset_count: entity.asset_entities.count,
          created_at: entity.created_at,
        }

        return base unless detailed

        base.merge(
          properties: entity.properties,
          external_ids: entity.external_ids,
          aliases: entity.entity_aliases.order(:alias_text).map { |a| { id: a.id, alias_text: a.alias_text, source: a.source } },
          canonical_id: entity.canonical_id,
          relationships: entity.asset_entities.group(:relationship).count,
          created_by: entity.created_by&.email,
          updated_at: entity.updated_at,
        )
      end
    end
  end
end
