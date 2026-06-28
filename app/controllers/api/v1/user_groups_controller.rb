# frozen_string_literal: true

module Api
  module V1
    # Read-only search endpoint used by the Folder Access tab to look up groups
    # when adding a policy.  Write operations (create/update/delete) remain in
    # the Admin namespace.
    #
    # == Endpoints
    #
    # | Method | Path                      | Description            |
    # |--------|---------------------------|------------------------|
    # | GET    | /api/v1/user_groups?q=... | Search groups by name  |
    class UserGroupsController < ApplicationController
      before_action :authenticate_hybrid!

      # GET /api/v1/user_groups?q=search_term&limit=20
      #
      # Returns groups whose name contains the query string (case-insensitive).
      # When +q+ is blank, returns the first +limit+ groups ordered by name.
      # Capped at 50 results to avoid accidental full-table dumps.
      def index
        limit  = [ params[:limit].to_i.clamp(1, 50), 20 ].max
        groups = UserGroup.order(:name).limit(limit)
        groups = groups.where("name ILIKE ?", "%#{params[:q].to_s.strip}%") if params[:q].present?

        render json: groups.map { |g| serialize_group(g) }
      end

      private

      def serialize_group(group)
        {
          id:          group.id,
          name:        group.name,
          slug:        group.slug,
          is_system:   group.is_system,
          description: group.description,
        }
      end
    end
  end
end
