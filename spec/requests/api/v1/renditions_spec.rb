# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Api::V1::Renditions', type: :request do
  rendition_schema = {
    type: :object,
    properties: {
      id: { type: :string, format: :uuid },
      asset_id: { type: :string, format: :uuid },
      kind: { type: :string, example: 'print_cmyk' },
      content_type: { type: :string, example: 'image/tiff', nullable: true },
      width: { type: :integer, nullable: true, description: 'Derived from the file, not supplied by the caller' },
      height: { type: :integer, nullable: true },
      file_size: { type: :integer, nullable: true },
      source: {
        type: :string,
        enum: %w[manual generated],
        description: 'Whether a person uploaded this or the processing pipeline produced it',
      },
      storage_backend: {
        type: :string,
        nullable: true,
        description: 'The backend the bytes were written to, recorded per row so it survives a provider switch',
      },
      metadata: { type: :object },
      url: { type: :string, nullable: true, description: 'Null when the backend cannot currently resolve it' },
      created_at: { type: :string, format: 'date-time' },
    },
  }

  path '/api/v1/assets/{asset_id}/renditions' do
    parameter name: :asset_id, in: :path, type: :string, required: true,
              description: 'Asset database ID or UUID'

    get 'List an asset\'s renditions' do
      tags 'Renditions'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Alternative stored forms of the same work — a print-ready CMYK TIFF, a
        hand-cropped social variant, a broadcast proxy.

        Renditions are not versions. A version answers "what did this asset look
        like at time T" and the newest one wins; a rendition answers "give me
        this asset in form X", and all of them are current at once.

        `storage_key` is deliberately absent. It is an internal address, and
        publishing it invites callers to build their own URLs against a backend
        layout that is not part of this contract.

        Requires `read` on the asset.
      DESC

      response '200', 'renditions listed' do
        let(:user) { FactoryBot.create(:user) }
        let(:asset_id) { FactoryBot.create(:asset, user: user).id }

        schema type: :object,
               properties: {
                 renditions: { type: :array, items: rendition_schema },
                 meta: { type: :object, properties: { total: { type: :integer } } },
               }
        run_test!
      end

      response '404', 'asset not found' do
        let(:asset_id) { '00000000-0000-0000-0000-000000000000' }
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end

    post 'Upload a manual rendition (multipart)' do
      tags 'Renditions'
      consumes 'multipart/form-data'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Stores a file as a named form of this asset.

        **`kind` is a key, not a label.** Lowercase words separated by
        underscores, unique per asset. The vocabulary is open — `print_cmyk`,
        `social_square`, `broadcast_proxy` — because which forms matter is an
        organisational question.

        **Reserved kinds.** `thumbnail`, `web_preview` and `poster` are produced
        by the processing pipeline and are rejected here. Other code is entitled
        to assume a thumbnail came from the thumbnailer.

        **Dimensions are derived, not accepted.** Width and height are read from
        the file itself; a caller that reported them wrongly would make every
        downstream layout decision wrong with it. Non-images simply have none.

        **Storage.** The rendition records the backend it was written to. If no
        backend is active the upload is refused with `503` rather than guessed
        at — storing somewhere we cannot name would produce a row we could never
        resolve again.

        Requires `modify` on the asset: adding a rendition changes what the
        asset is to every downstream consumer.
      DESC

      parameter name: :file, in: :formData, type: :string, format: :binary, required: true,
                description: 'Binary file to store'
      parameter name: :kind, in: :formData, type: :string, required: true,
                description: 'Lowercase underscored identifier, e.g. print_cmyk'
      parameter name: :metadata, in: :formData, type: :string, required: false,
                description: 'JSON object of extra fields, e.g. {"profile":"ISOcoated_v2"}'

      response '201', 'rendition stored' do
        let(:user) { FactoryBot.create(:user) }
        let(:asset_id) { FactoryBot.create(:asset, user: user).id }
        let(:kind) { 'print_cmyk' }
        let(:file) { fixture_file_upload(Rails.root.join('spec/fixtures/images/test-image.jpg'), 'image/jpeg') }

        before do
          FactoryBot.create(:storage_backend, active: true)
          allow_any_instance_of(StorageBackend).to receive(:adapter).and_return(
            instance_double(StorageAdapters::LocalStorageAdapter,
                            store: 'stored', delete: true, url: 'https://cdn.test/r.jpg'),
          )
        end

        schema rendition_schema
        run_test!
      end

      response '422', 'invalid kind, duplicate kind, reserved kind, or no file' do
        let(:user) { FactoryBot.create(:user) }
        let(:asset_id) { FactoryBot.create(:asset, user: user).id }
        let(:kind) { 'thumbnail' }
        let(:file) { fixture_file_upload(Rails.root.join('spec/fixtures/images/test-image.jpg'), 'image/jpeg') }

        schema type: :object,
               properties: {
                 error: { type: :string },
                 errors: { type: :array, items: { type: :string } },
                 reserved_kinds: { type: :array, items: { type: :string } },
               }
        run_test!
      end
    end
  end

  path '/api/v1/assets/{asset_id}/renditions/{id}' do
    parameter name: :asset_id, in: :path, type: :string, required: true
    parameter name: :id, in: :path, type: :string, required: true, description: 'Rendition UUID'

    delete 'Delete a rendition' do
      tags 'Renditions'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Removes the row **and** the stored object.

        There is no soft delete here. Unlike an asset, a rendition carries no
        history of its own, so a hidden row would be a file nobody can see and
        nobody can reclaim.

        Confined to the asset in the path: a rendition id cannot be used to
        reach across to another asset's derivative.

        Requires `modify` on the asset.
      DESC

      response '200', 'rendition deleted' do
        let(:user) { FactoryBot.create(:user) }
        let(:asset) { FactoryBot.create(:asset, user: user) }
        let(:asset_id) { asset.id }
        let(:id) { FactoryBot.create(:rendition, asset: asset, kind: 'print_cmyk').id }

        before do
          allow_any_instance_of(StorageBackend).to receive(:adapter).and_return(
            instance_double(StorageAdapters::LocalStorageAdapter, delete: true, url: 'https://cdn.test/r.jpg'),
          )
        end

        schema type: :object,
               properties: { id: { type: :string, format: :uuid }, deleted: { type: :boolean } }
        run_test!
      end

      response '404', 'rendition not found on this asset' do
        let(:user) { FactoryBot.create(:user) }
        let(:asset_id) { FactoryBot.create(:asset, user: user).id }
        let(:id) { '00000000-0000-0000-0000-000000000000' }

        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end
end
