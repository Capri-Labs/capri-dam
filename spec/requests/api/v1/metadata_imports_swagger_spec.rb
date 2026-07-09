require 'swagger_helper'

RSpec.describe 'Api::V1::MetadataImports docs', type: :request do
  path '/api/v1/metadata_imports/preview' do
    post 'Preview a metadata CSV import without persisting changes' do
      tags 'Metadata Imports'
      consumes 'multipart/form-data'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Parses a metadata CSV synchronously and returns per-row preview results without
        creating a `MetadataImport` record, mutating any `Asset`, attaching a results file,
        or launching workflows.
      DESC

      parameter name: :'metadata_import[source_file]', in: :formData, type: :string, format: :binary, required: true,
                description: 'CSV file to preview'
      parameter name: :'metadata_import[batch_size]', in: :formData, type: :integer, required: false,
                description: 'Rows processed per batch during parsing (1-100)'
      parameter name: :'metadata_import[field_separator]', in: :formData, type: :string, required: false,
                description: 'CSV field separator (defaults to comma)'
      parameter name: :'metadata_import[multi_value_delimiter]', in: :formData, type: :string, required: false,
                description: 'Delimiter used to split array-like cell values'
      parameter name: :'metadata_import[launch_workflows]', in: :formData, type: :boolean, required: false,
                description: 'Accepted for parity with create, but ignored during preview'
      parameter name: :'metadata_import[asset_path_column]', in: :formData, type: :string, required: false,
                description: 'Header name containing the absolute asset path'
      parameter name: :'metadata_import[ignored_columns][]', in: :formData, type: :string, required: false,
                description: 'Repeatable list of CSV columns to skip'
      parameter name: :'metadata_import[scheduled_at]', in: :formData, type: :string, required: false,
                description: 'Accepted for parity with create; preview always runs immediately'

      response '200', 'Preview generated successfully' do
        let(:user) { create(:user) }
        let(:'metadata_import[source_file]') do
          Rack::Test::UploadedFile.new(
            StringIO.new("asset_path,copyright\n/missing.jpg,ACME\n"),
            'text/csv',
            original_filename: 'metadata-preview.csv'
          )
        end
        let(:'metadata_import[batch_size]') { 50 }
        let(:'metadata_import[field_separator]') { ',' }
        let(:'metadata_import[multi_value_delimiter]') { '|' }
        let(:'metadata_import[launch_workflows]') { false }
        let(:'metadata_import[asset_path_column]') { 'asset_path' }

        before { sign_in user }

        schema type: :object,
               required: %w[dry_run total_rows success_count failure_count rows preview_csv],
               properties: {
                 dry_run: { type: :boolean, example: true },
                 name: { type: :string, example: 'metadata-preview.csv' },
                 batch_size: { type: :integer, example: 50 },
                 field_separator: { type: :string, example: ',' },
                 multi_value_delimiter: { type: :string, example: '|' },
                 launch_workflows: { type: :boolean, example: false },
                 asset_path_column: { type: :string, example: 'asset_path' },
                 ignored_columns: { type: :array, items: { type: :string } },
                 total_rows: { type: :integer, example: 1 },
                 success_count: { type: :integer, example: 0 },
                 failure_count: { type: :integer, example: 1 },
                 preview_csv: { type: :string },
                 rows: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       row_number: { type: :integer, example: 2 },
                       asset_path: { type: :string, example: '/Marketing/banner.jpg' },
                       resolved_asset_path: { type: :string, nullable: true, example: '/Marketing/banner.jpg' },
                       status: { type: :string, enum: %w[success fail], example: 'success' },
                       message: { type: :string, example: 'Updated 2 properties' },
                       changes: {
                         type: :array,
                         items: {
                           type: :object,
                           properties: {
                             field: { type: :string, example: 'copyright' },
                             from: {},
                             to: {},
                           },
                         },
                       },
                     },
                   },
                 },
               }

        run_test!
      end

      response '422', 'Preview validation failed' do
        before { sign_in create(:user) }

        schema type: :object,
               properties: {
                 errors: { type: :array, items: { type: :string } },
               }

        run_test!
      end
    end
  end
end
