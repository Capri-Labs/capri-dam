require "rails_helper"

RSpec.describe CustomNodeDefinition, type: :model do
  describe "validations" do
    it "requires a lowercase underscore key" do
      definition = build(:custom_node_definition, key: "Acme-Watermark")

      expect(definition).not_to be_valid
      expect(definition.errors[:key]).to be_present
    end

    it "requires a name" do
      definition = build(:custom_node_definition, name: "")

      expect(definition).not_to be_valid
      expect(definition.errors[:name]).to be_present
    end

    it "requires a supported status" do
      definition = build(:custom_node_definition, status: "archived")

      expect(definition).not_to be_valid
      expect(definition.errors[:status]).to be_present
    end

    it "requires config_schema to be field descriptor hashes" do
      definition = build(:custom_node_definition, config_schema: [ { "key" => "quality" } ])

      expect(definition).not_to be_valid
      expect(definition.errors[:config_schema]).to be_present
    end

    it "requires an HTTPS endpoint before enabling" do
      definition = build(:custom_node_definition, status: "enabled", runtime: { "endpoint_url" => "http://example.com" })

      expect(definition).not_to be_valid
      expect(definition.errors[:runtime]).to be_present
    end

    it "enforces unique keys" do
      create(:custom_node_definition, key: "acme_watermark")
      duplicate = build(:custom_node_definition, key: "acme_watermark")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:key]).to be_present
    end
  end

  describe "helpers" do
    it "exposes plugin node_type" do
      definition = build(:custom_node_definition, key: "acme_watermark")

      expect(definition.node_type).to eq("plugin:acme_watermark")
    end

    it "provides enum-like predicates" do
      expect(build(:custom_node_definition, status: "enabled")).to be_enabled
      expect(build(:custom_node_definition, status: "disabled")).to be_disabled
      expect(build(:custom_node_definition, status: "draft")).to be_draft
    end

    it "reports an open circuit at the threshold" do
      definition = build(:custom_node_definition, failure_count: described_class::CIRCUIT_BREAKER_THRESHOLD)

      expect(definition).to be_circuit_open
    end
  end

  describe ".enabled" do
    it "returns only enabled definitions" do
      enabled = create(:custom_node_definition, status: "enabled")
      create(:custom_node_definition, :disabled)
      create(:custom_node_definition, :draft)

      expect(described_class.enabled).to contain_exactly(enabled)
    end
  end
end
