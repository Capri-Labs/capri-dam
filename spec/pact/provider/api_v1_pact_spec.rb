# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Capri DAM API Pact provider", type: :request, aggregate_failures: true do
  contract = JSON.parse(File.read(Rails.root.join("pact/contracts/capri_dam_frontend-capri_dam_api.json")))

  # A fixed, never-seeded id/uuid used by the "*not found*" interactions
  # below — guaranteed not to collide with anything created in
  # {#seed_expanded_catalog!} since nothing in that method uses this literal.
  NONEXISTENT_UUID = "00000000-0000-0000-0000-000000000000"
  NONEXISTENT_ID    = 999_999_999

  before do
    allow_any_instance_of(ApplicationController).to receive(:authenticate_hybrid!).and_return(true)
    allow_any_instance_of(ApplicationController).to receive(:require_admin!).and_return(true)
    allow_any_instance_of(ApplicationController).to receive(:current_user) { User.where(admin: true).first || User.first }
  end

  def reset_contract_data!
    DatabaseCleaner.clean_with(:truncation)
  end

  # Real IDs/slugs/uuids captured while seeding {#seed_expanded_catalog!},
  # keyed by symbol. Interpolated into request paths/queries wherever a
  # `{{token}}` placeholder appears (see {#interpolate_seed_tokens}) — this
  # lets a single shared provider state back dozens of GET interactions
  # without hardcoding autoincrement/UUID values that would drift between
  # runs (every example truncates + reseeds the database).
  def seed_ids
    @seed_ids ||= {}
  end

  # Broad, shared provider state: creates one real record of (almost) every
  # top-level API resource so a large matrix of read-only GET interactions
  # can be verified against real, persisted data without each interaction
  # needing its own bespoke seeding. Deliberately reuses the same handful of
  # factories already exercised elsewhere in this suite.
  def seed_expanded_catalog!
    admin = create(:user, :admin, email: "catalog-admin@example.com", password: "password123")

    folder = create(:folder, user: admin, name: "Catalog Folder")
    schema_for_asset = create(:metadata_schema, :root, :with_basic_tab, name: "Catalog Asset Schema", slug: "catalog-asset-schema")
    asset  = create(:asset, user: admin, folder: folder, status: :ready, title: "Catalog Asset",
                     properties: { "content_type" => "image/jpeg", "tags" => [ "catalog" ],
                                   "applied_schema_id" => schema_for_asset.id })
    asset2 = create(:asset, user: admin, status: :ready, title: "Catalog Asset 2")

    collection = create(:collection, user: admin, name: "Catalog Collection", collection_type: "manual")
    group      = create(:user_group, name: "Catalog Group")
    create(:folder_policy, folder: folder, user_group: group, read_access: true)

    notification = create(:notification, user: admin, title: "Catalog Notification")
    email_template = create(:email_template)
    inbox_message  = create(:inbox_message, recipient: admin, email_template: email_template)

    workflow          = create(:workflow, name: "Catalog Workflow")
    create(:workflow_step, workflow: workflow)
    workflow_instance = create(:workflow_instance, asset: asset, workflow: workflow)

    ingestion_batch = create(:ingestion_batch, name: "Catalog Batch")
    ingestion_item  = create(:ingestion_item, ingestion_batch: ingestion_batch)
    connector       = create(:system_connector, name: "Catalog Connector")

    ai_batch_job    = create(:ai_batch_job, created_by: admin)
    ai_model_config = create(:ai_model_config)
    style_preset    = create(:style_preset, created_by: admin)
    agent_workflow  = create(:agent_workflow, created_by: admin)
    custom_node     = create(:custom_node_definition, created_by: admin)

    provenance_record = create(:asset_provenance_record, asset: asset2)
    duplicate_group   = create(:duplicate_group)
    quarantined_asset = create(:quarantined_asset, system_connector: connector)

    image_profile = create(:image_profile)
    video_profile = create(:video_profile)

    schema           = create(:metadata_schema, :root, name: "Catalog Schema", slug: "catalog-schema")
    metadata_export  = create(:metadata_export, user: admin)
    metadata_import  = create(:metadata_import, user: admin)
    asset_download   = create(:asset_download, user: admin, asset_ids: [ asset.uuid ])

    seed_ids.merge!(
      asset_id: asset.uuid,
      asset_id_2: asset2.uuid,
      folder_id: folder.id,
      collection_slug: collection.slug,
      user_group_id: group.id,
      notification_id: notification.id,
      inbox_message_id: inbox_message.id,
      workflow_id: workflow.id,
      workflow_instance_id: workflow_instance.id,
      ingestion_batch_id: ingestion_batch.id,
      ingestion_item_id: ingestion_item.id,
      system_connector_id: connector.id,
      ai_batch_job_id: ai_batch_job.id,
      ai_model_config_id: ai_model_config.id,
      style_preset_id: style_preset.id,
      agent_workflow_id: agent_workflow.id,
      custom_node_definition_id: custom_node.id,
      asset_provenance_record_id: provenance_record.id,
      duplicate_group_id: duplicate_group.id,
      quarantined_asset_id: quarantined_asset.id,
      image_profile_id: image_profile.id,
      video_profile_id: video_profile.id,
      metadata_schema_id: schema.id,
      metadata_export_id: metadata_export.id,
      metadata_import_id: metadata_import.id,
      asset_download_id: asset_download.id,
      nonexistent_uuid: NONEXISTENT_UUID,
      nonexistent_id: NONEXISTENT_ID,
    )
  end

  def seed_provider_state!(state_name)
    reset_contract_data!
    seed_ids.clear

    case state_name
    when "an admin user exists"
      user = create(:user, :admin, email: "admin@example.com", password: "password123")
      create(
        :asset,
        user: user,
        status: :ready,
        title: "Provider Asset",
        uuid: "5d8f6f8a-9e72-4fdd-a3f4-5e4bc6430c8d",
        properties: {
          "content_type" => "image/jpeg",
          "tags" => [],
          "search_hint" => "test",
          "storage_path" => "provider/provider-asset.jpg",
        }
      )
    when "a folder with assets exists"
      user = create(:user, :admin, email: "folder-admin@example.com", password: "password123")
      folder = create(:folder, user: user, name: "Provider Folder")
      create(:asset, user: user, folder: folder, status: :ready, title: "Folder Asset")
    when "an asset with a metadata schema exists"
      user = create(:user, :admin, email: "schema-admin@example.com", password: "password123")
      schema = create(:metadata_schema, :root, :with_basic_tab,
                      name: "Image", slug: "default", is_builtin: true)
      create(
        :asset,
        user: user,
        status: :ready,
        title: "Schema Asset",
        uuid: "a1b2c3d4-e5f6-4789-abcd-1234567890ab",
        properties: {
          "content_type" => "image/jpeg",
          "applied_schema_id" => schema.id,
          "embedded_metadata" => { "XMP" => { "Title" => "Sunset over the bay" } },
        }
      )
    when "no assets exist"
      nil
    when "asset uploads are accepted"
      create(:user, :admin, email: "upload-admin@example.com", password: "password123")
    when "notifications exist"
      user = create(:user, :admin, email: "notify-admin@example.com", password: "password123")
      create(:notification, user: user, message: "Provider notification", created_at: Time.zone.parse("2026-06-30T08:00:00Z"))
    when "collections exist"
      user = create(:user, :admin, email: "collection-admin@example.com", password: "password123")
      create(:collection, user: user, name: "Provider Collection", collection_type: "manual")
    when "the expanded catalog exists"
      seed_expanded_catalog!
    else
      raise "Unhandled provider state: #{state_name}"
    end
  end

  def expect_contract_subset(actual, expected, key: nil)
    if key.to_s == "id"
      expect(actual).to be_present
      return
    end

    case expected
    when Hash
      expected.each do |child_key, value|
        expect(actual).to have_key(child_key)
        expect_contract_subset(actual.fetch(child_key), value, key: child_key)
      end
    when Array
      expect(actual).to be_an(Array)
      expect(actual.size).to be >= expected.size
      expected.each_with_index do |value, index|
        if value.is_a?(Hash)
          matching_item = actual.find do |candidate|
            value.keys.all? { |child_key| candidate.is_a?(Hash) && candidate.key?(child_key) }
          end
          expect(matching_item).to be_present
          expect_contract_subset(matching_item, value)
        else
          expect_contract_subset(actual[index], value)
        end
      end
    when nil
      expect(actual).to be_nil
    when String
      if %w[id uuid thumb_url url created_at].include?(key.to_s)
        expect(actual).to be_present
      else
        expect(actual).to eq(expected)
      end
    else
      expect(actual).to eq(expected)
    end
  end

  # Replaces `{{token}}` placeholders in a request path/query string with the
  # real value captured in {#seed_ids} during {#seed_expanded_catalog!}. Lets
  # interactions reference dynamically-created records (UUID or bigint
  # primary keys) without baking non-deterministic IDs into the static
  # contract JSON.
  def interpolate_seed_tokens(value)
    return value if value.nil?

    value.gsub(/\{\{(\w+)\}\}/) do
      token = Regexp.last_match(1).to_sym
      seed_ids.fetch(token) { raise "Unknown seed token in contract fixture: #{token}" }.to_s
    end
  end

  contract.fetch("interactions").each do |interaction|
    description = interaction.fetch("description")
    provider_states = interaction.fetch("providerStates", []).map { |state| state.fetch("name") }
    request_spec = interaction.fetch("request")
    response_spec = interaction.fetch("response")

    it "honors pact interaction: #{description}" do
      provider_states.each { |state_name| seed_provider_state!(state_name) }

      path = interpolate_seed_tokens(request_spec.fetch("path"))
      query = interpolate_seed_tokens(request_spec["query"])
      path = "#{path}?#{query}" if query.present?
      headers = request_spec.fetch("headers", {}).merge("ACCEPT" => "application/json")
      body = request_spec["body"]

      send(request_spec.fetch("method").downcase, path, params: body, headers: headers)

      expect(response.status).to eq(response_spec.fetch("status"))

      next unless response_spec["body"]

      actual_body = JSON.parse(response.body)
      expect_contract_subset(actual_body, response_spec.fetch("body"))
    end
  end
end
