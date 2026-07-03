require "rails_helper"

RSpec.describe Api::V1::MetadataExportsController, type: :controller do
  describe "private serialization helpers" do
    it "serializes missing users and timestamps as nil" do
      export = build_stubbed(:metadata_export)
      allow(export).to receive(:user).and_return(nil)
      allow(export).to receive(:created_at).and_return(nil)
      allow(export).to receive(:scheduled_at).and_return(nil)
      allow(export).to receive(:expires_at).and_return(nil)

      expect(controller.send(:serialize, export)).to include(
        created_by: nil,
        created_at: nil,
        scheduled_at: nil,
        expires_at: nil
      )
    end

    it "falls back to the user email when the display name is blank" do
      export = build_stubbed(:metadata_export, user: build_stubbed(:user, name: nil, email: "owner@example.com"))

      expect(controller.send(:serialize, export)[:created_by]).to eq("owner@example.com")
    end

    it "ignores non-hash asset properties when collecting available keys" do
      # `properties` is a NOT NULL jsonb column, so it can never be a Ruby
      # `nil`, but jsonb accepts any valid JSON value (e.g. an array), which
      # is the realistic way a non-Hash value ends up in this column.
      create(:asset, properties: [])
      create(:asset, properties: { "copyright" => "ACME" })

      expect(controller.send(:collect_property_keys, nil, true)).to eq([ "copyright" ])
    end
  end
end
