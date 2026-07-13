# frozen_string_literal: true

require "swagger_helper"

# == Metadata Schemas API — rename, inheritance, and permission-gated writes
#
# Covers the fields/behaviors added for the Metadata Schemas rename +
# "Inherit From" + `metadata_users` permission-group feature:
#   * `name` is renameable via PATCH.
#   * `inherits_from_id` / `inherits_from_name` link a custom root schema
#     back to another root schema for tab inheritance.
#   * Write actions (create/update/destroy/duplicate/apply_to_folder/
#     remove_from_folder) require {User#metadata_schema_manager?} — i.e. an
#     admin, a member of `administrators`, or a member of the built-in
#     `metadata_users` group. Read actions remain open to all authenticated
#     users.
RSpec.describe "Api::V1::MetadataSchemas", type: :request do
  path "/api/v1/metadata_schemas/{id}" do
    patch "Update a metadata schema (rename / set Inherit From)" do
      tags "Metadata Schemas"
      consumes "application/json"
      produces "application/json"
      security [ Bearer: [] ]
      description "Renames a schema and/or sets its inherits_from_id. Requires metadata_schema_manager?."

      parameter name: :id, in: :path, type: :string
      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: {
          metadata_schema: {
            type: :object,
            properties: {
              name:             { type: :string, example: "Custom Product Images" },
              description:      { type: :string, nullable: true },
              inherits_from_id: { type: :integer, nullable: true, example: 12 },
              tabs:             { type: :array, items: { type: :object } },
            },
          },
        },
      }

      response "200", "schema updated" do
        let(:admin)         { create(:user, :admin) }
        let(:other_root)    { create(:metadata_schema, :root, name: "Default") }
        let(:id)            { create(:metadata_schema, :root, name: "Copy of Default").id }
        let(:payload)       { { metadata_schema: { name: "Copy of Default" } } }

        before { sign_in admin }

        schema type: :object,
               properties: {
                 id:                 { type: :integer },
                 name:               { type: :string },
                 level:              { type: :string },
                 inherits_from_id:   { type: :integer, nullable: true },
                 inherits_from_name: { type: :string, nullable: true },
                 tabs:               { type: :array, items: { type: :object } },
               }
        run_test! do
          expect(response.parsed_body["name"]).to eq("Copy of Default")
        end
      end

      response "403", "forbidden for users outside metadata_users" do
        let(:regular_user) { create(:user) }
        let(:id)           { create(:metadata_schema, :root).id }

        before { sign_in regular_user }

        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end

      response "422", "validation error (blank name, or circular/invalid inherits_from_id)" do
        let(:admin) { create(:user, :admin) }
        let(:id)    { create(:metadata_schema, :root).id }
        let(:payload) { { metadata_schema: { name: "" } } }

        before { sign_in admin }

        schema type: :object, properties: { errors: { type: :array, items: { type: :string } } }
        run_test!
      end
    end
  end

  path "/api/v1/metadata_schemas/{id}/duplicate" do
    post "Duplicate a metadata schema" do
      tags "Metadata Schemas"
      produces "application/json"
      security [ Bearer: [] ]
      description "Duplicates a schema tree. For root-level schemas, the copy links back via " \
                   "inherits_from instead of deep-copying tabs, so it starts with zero own tabs " \
                   "plus the source schema's tabs shown read-only. Requires metadata_schema_manager?."

      parameter name: :id, in: :path, type: :string

      response "201", "schema duplicated" do
        let(:admin) { create(:user, :admin) }
        let(:id)    { create(:metadata_schema, :root, :with_basic_tab, name: "Default").id }

        before { sign_in admin }

        schema type: :object,
               properties: {
                 id:               { type: :integer },
                 name:             { type: :string, example: "Copy of Default" },
                 inherits_from_id: { type: :integer, nullable: true },
                 tabs:             { type: :array, items: { type: :object } },
               }
        run_test!
      end

      response "403", "forbidden for users outside metadata_users" do
        let(:regular_user) { create(:user) }
        let(:id)           { create(:metadata_schema, :root).id }

        before { sign_in regular_user }

        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end

  path "/api/v1/metadata_schemas/bulk_delete" do
    delete "Bulk delete metadata schemas" do
      tags "Metadata Schemas"
      consumes "application/json"
      produces "application/json"
      security [ Bearer: [] ]
      description "Soft-deletes multiple schemas at once (with their descendants). " \
                   "Built-in schemas are silently skipped and reported in `skipped_builtin_ids`. " \
                   "Requires metadata_schema_manager?."

      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: {
          ids: { type: :array, items: { type: :integer }, example: [ 12, 13 ] },
        },
      }

      response "200", "schemas deleted (built-ins skipped)" do
        let(:admin)   { create(:user, :admin) }
        let(:schema1) { create(:metadata_schema, :root, name: "Deletable") }
        let(:payload) { { ids: [ schema1.id ] } }

        before { sign_in admin }

        schema type: :object,
               properties: {
                 deleted_count:        { type: :integer },
                 skipped_builtin_ids:  { type: :array, items: { type: :integer } },
               }
        run_test!
      end

      response "400", "no ids provided" do
        let(:admin)   { create(:user, :admin) }
        let(:payload) { {} }

        before { sign_in admin }

        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end

      response "403", "forbidden for users outside metadata_users" do
        let(:regular_user) { create(:user) }
        let(:payload)      { { ids: [ create(:metadata_schema, :root).id ] } }

        before { sign_in regular_user }

        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end
end
