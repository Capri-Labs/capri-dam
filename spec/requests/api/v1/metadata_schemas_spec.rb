require "rails_helper"

RSpec.describe "Api::V1::MetadataSchemas", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:schema) { create(:metadata_schema, :root, :with_basic_tab, name: "Default") }

  describe "permission gating for write actions" do
    let(:regular_user) { create(:user) }
    let(:metadata_member) do
      user  = create(:user)
      group = create(:user_group, :metadata_users)
      user.user_groups << group
      user
    end

    it "forbids a regular user from creating a schema" do
      sign_in regular_user

      expect do
        post api_v1_metadata_schemas_path,
             params: { metadata_schema: { name: "Products", level: "root", tabs: [] } },
             as: :json
      end.not_to change(MetadataSchema, :count)

      expect(response).to have_http_status(:forbidden)
    end

    it "forbids a regular user from updating a schema" do
      sign_in regular_user

      patch api_v1_metadata_schema_path(schema),
            params: { metadata_schema: { name: "Renamed" } },
            as: :json

      expect(response).to have_http_status(:forbidden)
      expect(schema.reload.name).to eq("Default")
    end

    it "forbids a regular user from duplicating a schema" do
      sign_in regular_user

      post duplicate_api_v1_metadata_schema_path(schema), as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "forbids a regular user from deleting a schema" do
      sign_in regular_user

      delete api_v1_metadata_schema_path(schema), as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "allows a member of metadata_users to create a schema" do
      sign_in metadata_member

      expect do
        post api_v1_metadata_schemas_path,
             params: { metadata_schema: { name: "Products", level: "root", tabs: [] } },
             as: :json
      end.to change(MetadataSchema, :count).by(1)

      expect(response).to have_http_status(:created)
    end

    it "still allows read access (index/show) for regular users" do
      sign_in regular_user

      get api_v1_metadata_schemas_path, as: :json
      expect(response).to have_http_status(:ok)

      get api_v1_metadata_schema_path(schema), as: :json
      expect(response).to have_http_status(:ok)
    end
  end

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

    it "persists select-field cascading rules (rules.cascade) through nested tabs/fields params" do
      sign_in admin

      patch api_v1_metadata_schema_path(schema),
            params: {
              metadata_schema: {
                tabs: [
                  {
                    id: "tab-1", name: "General", position: 0,
                    fields: [
                      {
                        id: "field-type", field_type: "select", label: "Asset Type",
                        map_to_property: "mamAssetType", position: 0,
                        options: [ { value: "Product", label: "Product" }, { value: "Lifestyle", label: "Lifestyle" } ]
                      },
                      {
                        id: "field-subtype", field_type: "select", label: "Asset Sub-Type",
                        map_to_property: "mamAssetSubType", position: 1,
                        options: [ { value: "In Pack", label: "In Pack" }, { value: "Motion", label: "Motion" } ],
                        rules: {
                          cascade: {
                            parent_field_id: "field-type",
                            map: { "Product" => [ "In Pack" ], "Lifestyle" => [ "Motion" ] },
                          },
                        }
                      },
                    ]
                  },
                ],
              },
            },
            as: :json

      expect(response).to have_http_status(:ok)
      persisted_field = schema.reload.tabs.first["fields"].second
      expect(persisted_field["rules"]["cascade"]).to eq(
        "parent_field_id" => "field-type",
        "map"             => { "Product" => [ "In Pack" ], "Lifestyle" => [ "Motion" ] }
      )
    end

    it "persists dynamic Requirement and Visibility rules (rules.requirement / rules.visibility) through nested tabs/fields params" do
      sign_in admin

      patch api_v1_metadata_schema_path(schema),
            params: {
              metadata_schema: {
                tabs: [
                  {
                    id: "tab-1", name: "Basic", position: 0,
                    fields: [
                      {
                        id: "field-license", field_type: "select", label: "License Requirements",
                        map_to_property: "license", position: 0,
                        options: [ { value: "Licensed", label: "Licensed" }, { value: "Unlicensed", label: "Unlicensed" } ]
                      },
                      {
                        id: "field-copyright", field_type: "text", label: "Copyright Owner",
                        map_to_property: "copyrightOwner", position: 1,
                        rules: {
                          requirement: { parent_field_id: "field-license", values: [ "Licensed" ] },
                        }
                      },
                      {
                        id: "field-country", field_type: "select", label: "Country",
                        map_to_property: "country", position: 2,
                        options: [ { value: "United States", label: "United States" }, { value: "Canada", label: "Canada" } ]
                      },
                      {
                        id: "field-state", field_type: "select", label: "State",
                        map_to_property: "state", position: 3,
                        options: [ { value: "California", label: "California" }, { value: "Florida", label: "Florida" } ],
                        rules: {
                          visibility: { parent_field_id: "field-country", values: [ "United States" ] },
                        }
                      },
                    ]
                  },
                ],
              },
            },
            as: :json

      expect(response).to have_http_status(:ok)
      fields = schema.reload.tabs.first["fields"]

      copyright_field = fields.find { |f| f["id"] == "field-copyright" }
      expect(copyright_field["rules"]["requirement"]).to eq(
        "parent_field_id" => "field-license",
        "values"          => [ "Licensed" ]
      )

      state_field = fields.find { |f| f["id"] == "field-state" }
      expect(state_field["rules"]["visibility"]).to eq(
        "parent_field_id" => "field-country",
        "values"          => [ "United States" ]
      )
    end

    it "renames a schema" do
      sign_in admin

      patch api_v1_metadata_schema_path(schema),
            params: { metadata_schema: { name: "Renamed Schema" } },
            as: :json

      expect(response).to have_http_status(:ok)
      expect(schema.reload.name).to eq("Renamed Schema")
    end

    it "sets and serializes inherits_from_id for root schemas" do
      sign_in admin
      other = create(:metadata_schema, :root, name: "Other Root")

      patch api_v1_metadata_schema_path(schema),
            params: { metadata_schema: { inherits_from_id: other.id } },
            as: :json

      expect(response).to have_http_status(:ok)
      expect(schema.reload.inherits_from_id).to eq(other.id)
      expect(response.parsed_body["inherits_from_id"]).to eq(other.id)
      expect(response.parsed_body["inherits_from_name"]).to eq("Other Root")
    end

    it "rejects inherits_from_id updates that would create a cycle" do
      sign_in admin
      other = create(:metadata_schema, :root, inherits_from: schema)

      patch api_v1_metadata_schema_path(schema),
            params: { metadata_schema: { inherits_from_id: other.id } },
            as: :json

      expect(response).to have_http_status(:unprocessable_entity)
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

  describe "DELETE /api/v1/metadata_schemas/bulk_delete" do
    it "soft deletes multiple non-built-in schemas" do
      sign_in admin
      other = create(:metadata_schema, :root, name: "Other")

      delete bulk_delete_api_v1_metadata_schemas_path,
             params: { ids: [ schema.id, other.id ] },
             as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["deleted_count"]).to eq(2)
      expect(schema.reload.deleted_at).to be_present
      expect(other.reload.deleted_at).to be_present
    end

    it "skips built-in schemas and reports them" do
      sign_in admin
      builtin = create(:metadata_schema, :root, :builtin)

      delete bulk_delete_api_v1_metadata_schemas_path,
             params: { ids: [ schema.id, builtin.id ] },
             as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["deleted_count"]).to eq(1)
      expect(response.parsed_body["skipped_builtin_ids"]).to eq([ builtin.id ])
      expect(schema.reload.deleted_at).to be_present
      expect(builtin.reload.deleted_at).to be_nil
    end

    it "returns bad_request when no ids are provided" do
      sign_in admin

      delete bulk_delete_api_v1_metadata_schemas_path, params: {}, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "forbids a regular user from bulk deleting" do
      sign_in create(:user)

      delete bulk_delete_api_v1_metadata_schemas_path,
             params: { ids: [ schema.id ] },
             as: :json

      expect(response).to have_http_status(:forbidden)
      expect(schema.reload.deleted_at).to be_nil
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

    it "links the duplicated root schema back via inherits_from instead of deep-copying tabs" do
      sign_in admin

      post duplicate_api_v1_metadata_schema_path(schema), as: :json

      expect(response).to have_http_status(:created)
      copy = MetadataSchema.find(response.parsed_body["id"])
      expect(copy.inherits_from_id).to eq(schema.id)
      expect(copy.tabs).to eq([])
      expect(copy.resolved_tabs.map { |t| t["name"] }).to include("Basic")
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
