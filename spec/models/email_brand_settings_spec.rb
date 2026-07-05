require "rails_helper"

RSpec.describe EmailBrandSettings, type: :model do
  describe ".from_raw" do
    it "builds a typed config from the persisted settings hash" do
      settings = described_class.from_raw(
        "custom_css" => "body { color: red; }",
        "primary_color" => "#ff0000",
        "font_family" => "Georgia, serif"
      )

      expect(settings.custom_css).to eq("body { color: red; }")
      expect(settings.primary_color).to eq("#ff0000")
      expect(settings.font_family).to eq("Georgia, serif")
    end

    it "defaults to an empty CSS block and brand defaults for blank input" do
      settings = described_class.from_raw(nil)

      expect(settings.custom_css).to eq("")
      expect(settings.primary_color).to eq("#1a56db")
      expect(settings.font_family).to eq("Arial, Helvetica, sans-serif")
    end
  end

  describe ".current" do
    it "loads the persisted email_brand_settings row" do
      Setting.set("email_brand_settings", "custom_css" => "a { color: blue; }")

      expect(described_class.current.custom_css).to eq("a { color: blue; }")
    end
  end

  describe "validations" do
    it "rejects custom CSS containing script tags" do
      settings = described_class.new(custom_css: "<script>alert(1)</script>")

      expect(settings).not_to be_valid
      expect(settings.errors[:custom_css]).to include("must not contain <script> tags")
    end

    it "rejects an invalid primary_color" do
      settings = described_class.new(primary_color: "not-a-color")

      expect(settings).not_to be_valid
      expect(settings.errors[:primary_color]).to be_present
    end

    it "rejects custom CSS exceeding the max length" do
      settings = described_class.new(custom_css: "a" * (described_class::MAX_CSS_LENGTH + 1))

      expect(settings).not_to be_valid
      expect(settings.errors[:custom_css]).to be_present
    end

    it "is valid with sane defaults" do
      expect(described_class.new).to be_valid
    end
  end

  describe "#persist!" do
    it "saves valid settings and returns true" do
      settings = described_class.new(custom_css: "p { margin: 0; }")

      expect(settings.persist!).to be(true)
      expect(described_class.current.custom_css).to eq("p { margin: 0; }")
    end

    it "does not persist and returns false when invalid" do
      settings = described_class.new(custom_css: "<script>bad()</script>")

      expect(settings.persist!).to be(false)
      expect(Setting.get("email_brand_settings")).to be_nil
    end
  end

  describe "#style_block" do
    it "wraps the custom CSS in a style tag" do
      settings = described_class.new(custom_css: "body { color: #1a56db; }")

      expect(settings.style_block).to eq("<style type=\"text/css\">\nbody { color: #1a56db; }\n</style>\n")
    end

    it "returns an empty string when no custom CSS is configured" do
      expect(described_class.new(custom_css: "").style_block).to eq("")
    end
  end
end
