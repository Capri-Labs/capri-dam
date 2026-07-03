require "rails_helper"

RSpec.describe MetadataSchemaSeeder do
  describe ".seed!" do
    it "creates the three built-in root schemas" do
      expect { described_class.seed! }.to change(MetadataSchema, :count).from(0)

      roots = MetadataSchema.active.roots.pluck(:slug)
      expect(roots).to contain_exactly("default", "collection", "product-images")
    end

    it "marks every created schema as builtin" do
      described_class.seed!
      expect(MetadataSchema.active.pluck(:is_builtin)).to all(be true)
    end

    it "builds the full Default MIME-type tree" do
      described_class.seed!

      default_root = MetadataSchema.active.roots.find_by(slug: "default")
      children     = default_root.children.active.pluck(:mime_segment)
      expect(children).to contain_exactly("image", "application", "video")

      image = default_root.children.active.find_by(mime_segment: "image")
      expect(image.children.active.pluck(:mime_segment)).to contain_exactly("jpeg", "png", "tiff", "gif", "webp")

      application = default_root.children.active.find_by(mime_segment: "application")
      expect(application.children.active.pluck(:mime_segment)).to contain_exactly("pdf", "zip")
    end

    it "includes the asset_type field on the Product Images schema" do
      described_class.seed!

      product_images = MetadataSchema.active.roots.find_by(slug: "product-images")
      product_tab    = product_images.tabs.find { |t| t["id"] == "tab-prod" }
      expect(product_tab["fields"].map { |f| f["map_to_property"] }).to include("dam:asset_type")
    end

    it "is idempotent — re-running it does not create duplicates" do
      described_class.seed!
      expect { described_class.seed! }.not_to change(MetadataSchema, :count)
    end

    it "does not overwrite customisations on an already-active builtin schema" do
      described_class.seed!
      default_root = MetadataSchema.active.roots.find_by(slug: "default")
      default_root.update!(description: "Customised by an admin")

      described_class.seed!

      expect(default_root.reload.description).to eq("Customised by an admin")
    end

    it "restores (un-soft-deletes) a builtin schema that was accidentally deleted" do
      described_class.seed!
      default_root = MetadataSchema.active.roots.find_by(slug: "default")
      default_root.soft_delete!
      expect(MetadataSchema.active.roots.find_by(slug: "default")).to be_nil

      described_class.seed!

      restored = MetadataSchema.active.roots.find_by(slug: "default")
      expect(restored).to be_present
      expect(restored.id).to eq(default_root.id)
    end

    it "flags a pre-existing custom schema with the same slug as builtin without touching its data" do
      custom = MetadataSchema.unscoped.find_by(slug: "collection") ||
               create(:metadata_schema, slug: "collection", name: "My Collection Override", is_builtin: false)

      described_class.seed!

      expect(custom.reload.is_builtin).to be(true)
      expect(custom.name).to eq("My Collection Override")
    end
  end

  describe ".upgrade_default_tabs!" do
    it "returns nil when the Default schema does not exist yet" do
      expect(described_class.upgrade_default_tabs!).to be_nil
    end

    it "adds the new XMP/Photoshop/ICC Profile tabs and corrects prefixes on a legacy Default schema" do
      # Simulate a legacy schema created before the prefix corrections/new tabs.
      legacy_root = create(
        :metadata_schema, slug: "default", name: "Default", level: "root", is_builtin: true,
        tabs: [
          { "id" => "tab-basic", "name" => "Basic", "position" => 0,
            "fields" => [ { "id" => "f1", "field_type" => "text", "label" => "Title", "map_to_property" => "dc:title", "position" => 0 } ] },
          { "id" => "tab-camera", "name" => "Camera", "position" => 2,
            "fields" => [ { "id" => "f2", "field_type" => "text", "label" => "Camera Make", "map_to_property" => "exif:Make", "position" => 0 } ] },
        ]
      )

      updated = described_class.upgrade_default_tabs!

      expect(updated.id).to eq(legacy_root.id)
      tab_ids = updated.tabs.map { |t| t["id"] }
      expect(tab_ids).to include("tab-xmp", "tab-photoshop", "tab-icc-profile")

      camera_tab = updated.tabs.find { |t| t["id"] == "tab-camera" }
      expect(camera_tab["fields"].map { |f| f["map_to_property"] }).to include("tiff:Make", "tiff:Model")
      expect(camera_tab["conditional"]).to be(true)
    end

    it "preserves a custom tab an admin added to the Default schema" do
      create(
        :metadata_schema, slug: "default", name: "Default", level: "root", is_builtin: true,
        tabs: [
          { "id" => "tab-basic", "name" => "Basic", "position" => 0, "fields" => [] },
          { "id" => "tab-custom-admin", "name" => "Admin Custom", "position" => 9, "fields" => [] },
        ]
      )

      updated = described_class.upgrade_default_tabs!

      tab_ids = updated.tabs.map { |t| t["id"] }
      expect(tab_ids).to include("tab-custom-admin")
    end

    it "is idempotent — re-running it does not duplicate tabs" do
      create(:metadata_schema, slug: "default", name: "Default", level: "root", is_builtin: true, tabs: [])

      described_class.upgrade_default_tabs!
      described_class.upgrade_default_tabs!

      updated = MetadataSchema.unscoped.find_by(slug: "default")
      expect(updated.tabs.map { |t| t["id"] }.tally.values).to all(eq(1))
    end
  end
end
