# frozen_string_literal: true

require "rails_helper"

RSpec.describe "EmptyBin mutation", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:storage_adapter) { instance_double("StorageAdapter", delete: true) }

  before do
    allow(Redis).to receive(:new).and_return(instance_double(Redis, publish: true))
  end

  def gql(query, user: admin)
    sign_in(user) if user
    post "/graphql",
         params: { query: query },
         headers: { "Accept" => "application/json" },
         as: :json
    JSON.parse(response.body)
  end

  def schema_gql(query, user:)
    HeadlessDamSchema.execute(query, context: { current_user: user }).to_h
  end

  describe "mutation { emptyBin }" do
    let(:mutation) { "mutation { emptyBin(input: {}) { deleted errors } }" }

    it "requires authentication" do
      body = schema_gql(mutation, user: nil)

      expect(body.dig("data", "emptyBin", "deleted")).to be_nil
      expect(body.dig("data", "emptyBin", "errors")).to include("Authentication required.")
    end

    it "permanently deletes trashed folders and assets, including storage paths" do
      folder = create(:folder, :trashed)
      asset = create(:asset, :trashed)
      create(:asset_version, asset: asset, properties: { "storage_path" => "assets/original.jpg" })
      allow(StorageBackend).to receive(:find_by).with(active: true).and_return(instance_double(StorageBackend))
      allow(StorageManager).to receive(:adapter_for).and_return(storage_adapter)

      body = gql(mutation)

      expect(body.dig("data", "emptyBin")).to eq("deleted" => 2, "errors" => [])
      expect(storage_adapter).to have_received(:delete).with("assets/original.jpg")
      expect { folder.reload }.to raise_error(ActiveRecord::RecordNotFound)
      expect { asset.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "continues without storage when no active backend exists" do
      create(:asset, :trashed)
      allow(StorageBackend).to receive(:find_by).with(active: true).and_return(nil)
      expect(StorageManager).not_to receive(:adapter_for)

      body = gql(mutation)

      expect(body.dig("data", "emptyBin")).to eq("deleted" => 1, "errors" => [])
    end

    it "purges attached version files even when no storage_path is present" do
      asset = create(:asset, :trashed)
      version = create(:asset_version, asset: asset, properties: {})
      version.file.attach(
        io: StringIO.new("binary"),
        filename: "version.bin",
        content_type: "application/octet-stream"
      )
      allow(StorageBackend).to receive(:find_by).with(active: true).and_return(nil)

      body = gql(mutation)

      expect(body.dig("data", "emptyBin")).to eq("deleted" => 1, "errors" => [])
      expect { version.reload }.to raise_error(ActiveRecord::RecordNotFound)
      expect(ActiveStorage::Attachment.where(record_type: "AssetVersion", record_id: version.id)).to be_empty
    end

    it "skips storage deletion when no backend exists but still purges attached files" do
      asset = create(:asset, :trashed)
      version = create(:asset_version, asset: asset, properties: { "storage_path" => "assets/original.jpg" })
      version.file.attach(
        io: StringIO.new("binary"),
        filename: "version.bin",
        content_type: "application/octet-stream"
      )
      allow(StorageBackend).to receive(:find_by).with(active: true).and_return(nil)
      expect(StorageManager).not_to receive(:adapter_for)

      body = gql(mutation)

      expect(body.dig("data", "emptyBin")).to eq("deleted" => 1, "errors" => [])
      expect { version.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "returns rescued errors" do
      allow(Folder).to receive(:trashed).and_raise(StandardError, "database unavailable")

      body = gql(mutation)

      expect(body.dig("data", "emptyBin", "deleted")).to be_nil
      expect(body.dig("data", "emptyBin", "errors")).to include("database unavailable")
    end
  end
end
