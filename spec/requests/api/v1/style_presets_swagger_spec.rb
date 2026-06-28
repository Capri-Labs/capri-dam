# frozen_string_literal: true

require "swagger_helper"

RSpec.describe "Api::V1::StylePresets", type: :request do
  # ===========================================================================
  # LIST — GET /api/v1/style_presets
  # ===========================================================================
  path "/api/v1/style_presets" do
    get "List style presets" do
      tags "Style & Model Hub"
      produces "application/json"
      security [ Bearer: [] ]
      description "Returns all brand/style presets. Admin only."
      parameter name: :active, in: :query, type: :boolean, required: false,
                description: "Filter to active presets only"

      response "200", "List of style presets" do
        schema type: :object,
               properties: {
                 total:   { type: :integer },
                 presets: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       id:          { type: :integer },
                       name:        { type: :string },
                       slug:        { type: :string, example: "editorial-dark" },
                       description: { type: :string, nullable: true },
                       active:      { type: :boolean },
                       is_default:  { type: :boolean },
                       style_params: { type: :object },
                       gateway_ref:  { type: :string, nullable: true },
                       synced_at:    { type: :string, format: "date-time", nullable: true },
                       stale:        { type: :boolean },
                       created_by:   { type: :string, nullable: true },
                       created_at:   { type: :string, format: "date-time" },
                       updated_at:   { type: :string, format: "date-time" },
                     },
                   },
                 },
               }
        run_test!
      end

      response "401", "Unauthenticated" do
        run_test!
      end

      response "403", "Forbidden (admin only)" do
        run_test!
      end
    end

    post "Create a style preset" do
      tags "Style & Model Hub"
      consumes "application/json"
      produces "application/json"
      security [ Bearer: [] ]
      description "Creates a new brand/style preset. Slug is auto-derived from name if omitted."

      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: [ "style_preset" ],
        properties: {
          style_preset: {
            type: :object,
            required: [ "name" ],
            properties: {
              name:         { type: :string, example: "Editorial Dark" },
              description:  { type: :string, nullable: true },
              active:       { type: :boolean, example: true },
              style_params: {
                type: :object,
                example: { "tone" => "editorial", "palette" => [ "#1a1a1a", "#ffffff" ] },
              },
            },
          },
        },
      }

      response "201", "Style preset created" do
        run_test!
      end

      response "422", "Validation error" do
        run_test!
      end
    end
  end

  # ===========================================================================
  # SHOW / UPDATE / DELETE — /api/v1/style_presets/:id
  # ===========================================================================
  path "/api/v1/style_presets/{id}" do
    parameter name: :id, in: :path, type: :integer, required: true, description: "Style preset ID"

    get "Fetch a single style preset" do
      tags "Style & Model Hub"
      produces "application/json"
      security [ Bearer: [] ]

      response "200", "Style preset found" do
        run_test!
      end

      response "404", "Not found" do
        run_test!
      end
    end

    patch "Update a style preset" do
      tags "Style & Model Hub"
      consumes "application/json"
      produces "application/json"
      security [ Bearer: [] ]

      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: {
          style_preset: {
            type: :object,
            properties: {
              name:         { type: :string },
              description:  { type: :string, nullable: true },
              active:       { type: :boolean },
              style_params: { type: :object },
            },
          },
        },
      }

      response "200", "Updated" do
        run_test!
      end
    end

    delete "Delete a style preset" do
      tags "Style & Model Hub"
      produces "application/json"
      security [ Bearer: [] ]

      response "200", "Deleted" do
        run_test!
      end
    end
  end

  # ===========================================================================
  # SYNC — POST /api/v1/style_presets/:id/sync
  # ===========================================================================
  path "/api/v1/style_presets/{id}/sync" do
    parameter name: :id, in: :path, type: :integer, required: true

    post "Queue a gateway sync for a style preset" do
      tags "Style & Model Hub"
      produces "application/json"
      security [ Bearer: [] ]
      description "Enqueues StylePresetSyncWorker to push this preset to the AI Gateway via Redis pub/sub."

      response "200", "Sync queued" do
        run_test!
      end
    end
  end

  # ===========================================================================
  # SET DEFAULT — POST /api/v1/style_presets/:id/set_default
  # ===========================================================================
  path "/api/v1/style_presets/{id}/set_default" do
    parameter name: :id, in: :path, type: :integer, required: true

    post "Promote style preset to organisation default" do
      tags "Style & Model Hub"
      produces "application/json"
      security [ Bearer: [] ]
      description "Sets is_default=true for this preset and demotes any existing default."

      response "200", "Default updated" do
        run_test!
      end
    end
  end
end
