# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Api::V1::MetadataSchemas', type: :request do
  # ===========================================================================
  # INDEX — GET /api/v1/metadata_schemas
  # ===========================================================================
  path '/api/v1/metadata_schemas' do
    get 'List all root metadata schemas (with children)' do
      tags        'Metadata Schemas'
      produces    'application/json'
      security    [ Bearer: [] ]
      description <<~DESC
        Returns all active root-level metadata schemas, each fully populated with
        their type and subtype children. Schemas are ordered: built-in first, then
        alphabetically by name.
      DESC

      response '200', 'Schemas returned' do
        schema type: :array,
               items: {
                 '$ref' => '#/components/schemas/MetadataSchema',
               }

        let(:Authorization) { 'Bearer test-token' }

        before do
          create(:metadata_schema, :root, :with_basic_tab, name: 'Default', is_builtin: true)
          create(:metadata_schema, :root, name: 'Product Images')
        end

        run_test!
      end

      response '401', 'Unauthorized' do
        let(:Authorization) { nil }
        run_test!
      end
    end

    # ─── CREATE ───────────────────────────────────────────────────────────────
    post 'Create a new metadata schema' do
      tags        'Metadata Schemas'
      consumes    'application/json'
      produces    'application/json'
      security    [ Bearer: [] ]

      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          metadata_schema: {
            type: :object,
            required: %w[name level],
            properties: {
              name:         { type: :string,  example: 'Magazine Assets' },
              description:  { type: :string,  example: 'Schema for magazine photography' },
              level:        { type: :string,  example: 'root', enum: %w[root type subtype] },
              parent_id:    { type: :integer, nullable: true },
              mime_segment: { type: :string,  nullable: true, example: 'image' },
              tabs:         { type: :array,   items: { type: :object } },
            },
          },
        },
      }

      response '201', 'Schema created' do
        schema '$ref' => '#/components/schemas/MetadataSchema'

        let(:Authorization) { 'Bearer test-token' }
        let(:body) { { metadata_schema: { name: 'Magazine Assets', level: 'root', tabs: [] } } }

        run_test!
      end

      response '422', 'Validation error' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:Authorization) { 'Bearer test-token' }
        let(:body) { { metadata_schema: { name: '', level: 'root' } } }

        run_test!
      end
    end
  end

  # ===========================================================================
  # SHOW — GET /api/v1/metadata_schemas/:id
  # ===========================================================================
  path '/api/v1/metadata_schemas/{id}' do
    parameter name: :id, in: :path, type: :integer, required: true,
              description: 'Metadata schema ID'

    get 'Retrieve a single metadata schema' do
      tags     'Metadata Schemas'
      produces 'application/json'
      security [ Bearer: [] ]
      description 'Returns the schema including `resolved_tabs` which merges inherited tabs from the parent chain.'

      response '200', 'Schema returned' do
        schema '$ref' => '#/components/schemas/MetadataSchema'

        let(:Authorization) { 'Bearer test-token' }
        let(:id) { create(:metadata_schema, :root).id }

        run_test!
      end

      response '404', 'Not found' do
        let(:Authorization) { 'Bearer test-token' }
        let(:id) { 0 }

        run_test!
      end
    end

    # ─── UPDATE ───────────────────────────────────────────────────────────────
    patch 'Update a metadata schema' do
      tags     'Metadata Schemas'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]

      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          metadata_schema: {
            type: :object,
            properties: {
              name:        { type: :string },
              description: { type: :string },
              tabs:        { type: :array, items: { type: :object } },
            },
          },
        },
      }

      response '200', 'Schema updated' do
        schema '$ref' => '#/components/schemas/MetadataSchema'

        let(:Authorization) { 'Bearer test-token' }
        let(:id)   { create(:metadata_schema, :root).id }
        let(:body) { { metadata_schema: { name: 'Updated Name' } } }

        run_test!
      end

      response '422', 'Validation error' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:Authorization) { 'Bearer test-token' }
        let(:id)   { create(:metadata_schema, :root).id }
        let(:body) { { metadata_schema: { name: '' } } }

        run_test!
      end
    end

    # ─── DESTROY ──────────────────────────────────────────────────────────────
    delete 'Soft-delete a metadata schema' do
      tags     'Metadata Schemas'
      produces 'application/json'
      security [ Bearer: [] ]
      description 'Soft-deletes the schema and all its child schemas. Built-in schemas cannot be deleted.'

      response '204', 'Deleted' do
        let(:Authorization) { 'Bearer test-token' }
        let(:id) { create(:metadata_schema, :root, is_builtin: false).id }

        run_test!
      end

      response '403', 'Forbidden — built-in schema' do
        let(:Authorization) { 'Bearer test-token' }
        let(:id) { create(:metadata_schema, :root, is_builtin: true).id }

        run_test!
      end
    end
  end

  # ===========================================================================
  # DUPLICATE — POST /api/v1/metadata_schemas/:id/duplicate
  # ===========================================================================
  path '/api/v1/metadata_schemas/{id}/duplicate' do
    parameter name: :id, in: :path, type: :integer, required: true

    post 'Deep-duplicate a schema tree' do
      tags     'Metadata Schemas'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Creates a deep copy of the schema and all its children. The copy is
        non-builtin and named "Copy of \<original name\>". This is the recommended
        way to start a new custom schema based on an existing one.
      DESC

      response '201', 'Duplicate created' do
        schema '$ref' => '#/components/schemas/MetadataSchema'

        let(:Authorization) { 'Bearer test-token' }
        let(:id) { create(:metadata_schema, :root, :builtin, :with_basic_tab).id }

        run_test!
      end
    end
  end

  # ===========================================================================
  # APPLY TO FOLDER — POST /api/v1/metadata_schemas/:id/apply_to_folder
  # ===========================================================================
  path '/api/v1/metadata_schemas/{id}/apply_to_folder' do
    parameter name: :id, in: :path, type: :integer, required: true

    post 'Apply a root schema to a folder' do
      tags     'Metadata Schemas'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]

      parameter name: :body, in: :body, schema: {
        type: :object,
        required: %w[folder_id],
        properties: { folder_id: { type: :string, format: :uuid } },
      }

      response '201', 'Assignment created' do
        let(:Authorization) { 'Bearer test-token' }
        let(:id)   { create(:metadata_schema, :root).id }
        let(:body) { { folder_id: SecureRandom.uuid } }

        run_test!
      end

      response '400', 'folder_id missing' do
        let(:Authorization) { 'Bearer test-token' }
        let(:id)   { create(:metadata_schema, :root).id }
        let(:body) { {} }

        run_test!
      end
    end
  end

  # ===========================================================================
  # REMOVE FROM FOLDER — DELETE /api/v1/metadata_schemas/:id/remove_from_folder
  # ===========================================================================
  path '/api/v1/metadata_schemas/{id}/remove_from_folder' do
    parameter name: :id, in: :path, type: :integer, required: true

    delete 'Remove a schema from a folder' do
      tags     'Metadata Schemas'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]

      parameter name: :body, in: :body, schema: {
        type: :object,
        required: %w[folder_id],
        properties: { folder_id: { type: :string, format: :uuid } },
      }

      response '204', 'Removed' do
        let(:Authorization) { 'Bearer test-token' }
        let(:id)   { create(:metadata_schema, :root).id }
        let(:body) { { folder_id: SecureRandom.uuid } }

        run_test!
      end
    end
  end
end
