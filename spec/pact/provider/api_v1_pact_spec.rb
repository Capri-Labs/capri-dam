# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Capri DAM API Pact provider", type: :request, aggregate_failures: true do
  contract = JSON.parse(File.read(Rails.root.join("pact/contracts/capri_dam_frontend-capri_dam_api.json")))

  before do
    allow_any_instance_of(ApplicationController).to receive(:authenticate_hybrid!).and_return(true)
    allow_any_instance_of(ApplicationController).to receive(:require_admin!).and_return(true)
    allow_any_instance_of(ApplicationController).to receive(:current_user) { User.where(admin: true).first || User.first }
  end

  def reset_contract_data!
    DatabaseCleaner.clean_with(:truncation)
  end

  def seed_provider_state!(state_name)
    reset_contract_data!

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

  contract.fetch("interactions").each do |interaction|
    description = interaction.fetch("description")
    provider_states = interaction.fetch("providerStates", []).map { |state| state.fetch("name") }
    request_spec = interaction.fetch("request")
    response_spec = interaction.fetch("response")

    it "honors pact interaction: #{description}" do
      provider_states.each { |state_name| seed_provider_state!(state_name) }

      path = request_spec.fetch("path")
      path = "#{path}?#{request_spec["query"]}" if request_spec["query"].present?
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
