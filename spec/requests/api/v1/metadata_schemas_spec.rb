require "rails_helper"

RSpec.describe "Api::V1::MetadataSchemas", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:schema) { create(:metadata_schema, :root, :with_basic_tab, name: "Default") }

  describe "GET /api/v1/metadata_schemas" do
    it "requires authentication" do
      get api_v1_metadata_schemas_path, as: :json

      expect(response.status).to be_in([ 401, 302 ])
    end

    it "returns root schemas with children" do
      sign_in admin
      child = create(:metadata_schema, :type_level, parent: schema, name: "Image", mime_segment: "image")

      get api_v1_metadata_schemas_path, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.first["id"]).to eq(schema.id)
      expect(response.parsed_body.first["children"].first["id"]).to eq(child.id)
    end
  end

  describe "GET /api/v1/metadata_schemas/:id" do
    it "returns a schema with resolved tabs" do
      sign_in admin
      child = create(:metadata_schema, :type_level, parent: schema, name: "Image", mime_segment: "image")

      get api_v1_metadata_schema_path(child), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["resolved_tabs"]).not_to be_empty
    end

    it "returns not found for unknown ids" do
      sign_in admin

      get api_v1_metadata_schema_path("missing"), as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/metadata_schemas" do
    it "creates a schema" do
      sign_in admin

      expect do
        post api_v1_metadata_schemas_path,
             params: { metadata_schema: { name: "Products", level: "root", tabs: [] } },
             as: :json
      end.to change(MetadataSchema, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["name"]).to eq("Products")
    end

    it "returns validation errors" do
      sign_in admin

      post api_v1_metadata_schemas_path,
           params: { metadata_schema: { name: "", level: "type", tabs: [] } },
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["errors"]).not_to be_empty
    end
  end

  describe "PATCH /api/v1/metadata_schemas/:id" do
    it "updates a schema" do
      sign_in admin

      patch api_v1_metadata_schema_path(schema),
            params: { metadata_schema: { description: "Updated" } },
            as: :json

      expect(response).to have_http_status(:ok)
      expect(schema.reload.description).to eq("Updated")
    end

    it "returns validation errors for invalid updates" do
      sign_in admin

      patch api_v1_metadata_schema_path(schema),
            params: { metadata_schema: { name: "" } },
            as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["errors"]).to include("Name can't be blank")
    end
  end

  describe "DELETE /api/v1/metadata_schemas/:id" do
    it "soft deletes non-built-in schemas" do
      sign_in admin

      delete api_v1_metadata_schema_path(schema), as: :json

      expect(response).to have_http_status(:no_content)
      expect(schema.reload.deleted_at).to be_present
    end

    it "rejects deletion of built-in schemas" do
      sign_in admin
      builtin = create(:metadata_schema, :root, :builtin)

      delete api_v1_metadata_schema_path(builtin), as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /api/v1/metadata_schemas/:id/duplicate" do
    it "duplicates the schema tree" do
      sign_in admin
      create(:metadata_schema, :type_level, parent: schema, name: "Image", mime_segment: "image")

      expect do
        post duplicate_api_v1_metadata_schema_path(schema), as: :json
      end.to change(MetadataSchema, :count).by(2)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["name"]).to start_with("Copy of ")
    end

    it "returns an error when duplication fails" do
      sign_in admin
      allow_any_instance_of(Api::V1::MetadataSchemasController)
        .to receive(:deep_duplicate)
        .and_raise(StandardError, "duplicate failed")

      post duplicate_api_v1_metadata_schema_path(schema), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq("error" => "duplicate failed")
    end
  end

  describe "POST /api/v1/metadata_schemas/:id/apply_to_folder" do
    it "creates a folder assignment" do
      sign_in admin
      folder = create(:folder, user: admin)

      expect do
        post apply_to_folder_api_v1_metadata_schema_path(schema),
             params: { folder_id: folder.id },
             as: :json
      end.to change(MetadataSchemaFolderAssignment, :count).by(1)

      expect(response).to have_http_status(:created)
    end

    it "rejects blank folder ids" do
      sign_in admin

      post apply_to_folder_api_v1_metadata_schema_path(schema), params: {}, as: :json

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "DELETE /api/v1/metadata_schemas/:id/remove_from_folder" do
    it "removes an existing folder assignment" do
      sign_in admin
      folder = create(:folder, user: admin)
      create(:metadata_schema_folder_assignment, metadata_schema: schema, folder_id: folder.id)

      expect do
        delete remove_from_folder_api_v1_metadata_schema_path(schema),
               params: { folder_id: folder.id },
               as: :json
      end.to change(MetadataSchemaFolderAssignment, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end
  end

  describe "GET /api/v1/metadata_schemas/:id/folders" do
    it "returns folders assigned to the schema" do
      sign_in admin
      folder = create(:folder, user: admin, name: "Schema Folder")
      create(:metadata_schema_folder_assignment, metadata_schema: schema, folder_id: folder.id)

      get folders_api_v1_metadata_schema_path(schema), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include(
        a_hash_including("id" => folder.id, "name" => "Schema Folder", "path" => folder.path)
      )
    end
  end
end
