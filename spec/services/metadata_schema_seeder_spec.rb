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
end
