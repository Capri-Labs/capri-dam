require "rails_helper"

RSpec.describe MamGlobalDemoSchemaSeeder do
  describe ".seed!" do
    it "creates the 'MAM Global' root schema with the expected slug" do
      expect { described_class.seed! }.to change(MetadataSchema, :count).by(1)

      schema = MetadataSchema.active.roots.find_by(slug: "mam-global-demo")
      expect(schema).to be_present
      expect(schema.name).to eq("MAM Global")
      expect(schema.is_builtin).to be(false)
    end

    it "is idempotent — re-running it updates the existing schema instead of duplicating it" do
      described_class.seed!
      expect { described_class.seed! }.not_to change(MetadataSchema, :count)
    end

    it "restores a soft-deleted demo schema instead of creating a duplicate" do
      schema = described_class.seed!
      schema.soft_delete!

      expect { described_class.seed! }.not_to change(MetadataSchema.unscoped, :count)
      expect(MetadataSchema.active.find_by(slug: "mam-global-demo")).to be_present
    end

    it "builds the Asset Type field with a Product/Lifestyle/Brand dropdown" do
      schema = described_class.seed!
      tab    = schema.tabs.first
      field  = tab["fields"].find { |f| f["map_to_property"] == "mamAssetType" }

      expect(field["field_type"]).to eq("select")
      expect(field["required"]).to be(true)
      expect(field["options"].map { |o| o["value"] }).to contain_exactly("Product", "Lifestyle", "Brand")
    end

    it "cascades Asset Sub-Type options from the Asset Type field, matching the source XML's cascadeitems" do
      schema      = described_class.seed!
      tab         = schema.tabs.first
      asset_type  = tab["fields"].find { |f| f["map_to_property"] == "mamAssetType" }
      sub_type    = tab["fields"].find { |f| f["map_to_property"] == "mamAssetSubType" }

      cascade = sub_type["rules"]["cascade"]
      expect(cascade["parent_field_id"]).to eq(asset_type["id"])
      expect(cascade["map"]["Product"]).to include("In Pack", "Render")
      expect(cascade["map"]["Lifestyle"]).to include("Motion", "Recipe")
      expect(cascade["map"]["Brand"]).to include("Badges", "Background")
    end

    it "cascades Commodity Group options from the Category Group field" do
      schema          = described_class.seed!
      tab             = schema.tabs.first
      category_group  = tab["fields"].find { |f| f["map_to_property"] == "mamCategoryGroup" }
      commodity_group = tab["fields"].find { |f| f["map_to_property"] == "mamCommodityGroup" }

      cascade = commodity_group["rules"]["cascade"]
      expect(cascade["parent_field_id"]).to eq(category_group["id"])
      expect(cascade["map"]["0001"]).to contain_exactly("000101", "000102", "000103", "000104")
    end

    it "marks the read-only 'Date of upload' field accordingly" do
      schema = described_class.seed!
      field  = schema.tabs.first["fields"].find { |f| f["map_to_property"] == "mamDateOfUpload" }

      expect(field["field_type"]).to eq("date")
      expect(field["read_only"]).to be(true)
    end
  end

  describe ".remove!" do
    it "soft-deletes the demo schema" do
      described_class.seed!
      expect { described_class.remove! }.to change { MetadataSchema.active.exists?(slug: "mam-global-demo") }.from(true).to(false)
    end

    it "is a no-op when the demo schema does not exist" do
      expect { described_class.remove! }.not_to raise_error
    end
  end
end
