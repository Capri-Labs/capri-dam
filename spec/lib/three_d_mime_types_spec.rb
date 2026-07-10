require "rails_helper"

RSpec.describe ThreeDMimeTypes do
  describe ".model_3d?" do
    it "recognises all six supported 3D MIME types" do
      %w[
        model/gltf-binary
        model/gltf+json
        application/x-tgif
        application/vnd.ms-pki.stl
        model/x-adobe-dn
        model/vnd.usdz+zip
      ].each do |mime|
        expect(described_class.model_3d?(mime)).to be(true)
      end
    end

    it "returns false for non-3D MIME types" do
      expect(described_class.model_3d?("image/png")).to be(false)
      expect(described_class.model_3d?("application/pdf")).to be(false)
      expect(described_class.model_3d?(nil)).to be(false)
    end
  end

  describe ".renderable?" do
    it "is true for glTF/GLB (model-viewer) and OBJ/STL (three.js)" do
      expect(described_class.renderable?("model/gltf-binary")).to be(true)
      expect(described_class.renderable?("model/gltf+json")).to be(true)
      expect(described_class.renderable?("application/x-tgif")).to be(true)
      expect(described_class.renderable?("application/vnd.ms-pki.stl")).to be(true)
    end

    it "is false for USDZ and Adobe Dimension (no in-page WebGL renderer)" do
      expect(described_class.renderable?("model/vnd.usdz+zip")).to be(false)
      expect(described_class.renderable?("model/x-adobe-dn")).to be(false)
    end

    it "is false for non-3D MIME types" do
      expect(described_class.renderable?("image/png")).to be(false)
    end
  end

  describe "MIME_TO_EXTENSION" do
    it "maps each MIME type to its canonical extension" do
      expect(described_class::MIME_TO_EXTENSION).to eq(
        "model/gltf-binary" => "glb",
        "model/gltf+json" => "gltf",
        "application/x-tgif" => "obj",
        "application/vnd.ms-pki.stl" => "stl",
        "model/x-adobe-dn" => "dn",
        "model/vnd.usdz+zip" => "usdz"
      )
    end
  end

  # Regression test for config/initializers/three_d_mime_types.rb: without
  # registering these extensions with Marcel, `Marcel::MimeType.for` (used by
  # AssetProcessorWorker on every upload) falls back to the generic
  # `application/octet-stream` — or, for USDZ specifically, misdetects it as
  # `application/zip` since a USDZ file is literally a ZIP archive under the
  # hood — and the 3D viewer / media-type classification never engages for
  # real-world uploads.
  describe "Marcel MIME registration (config/initializers/three_d_mime_types.rb)" do
    it "recognises every supported 3D extension by filename alone" do
      expect(Marcel::MimeType.for(name: "model.glb")).to eq("model/gltf-binary")
      expect(Marcel::MimeType.for(name: "model.gltf")).to eq("model/gltf+json")
      expect(Marcel::MimeType.for(name: "model.obj")).to eq("application/x-tgif")
      expect(Marcel::MimeType.for(name: "model.stl")).to eq("application/vnd.ms-pki.stl")
      expect(Marcel::MimeType.for(name: "model.dn")).to eq("model/x-adobe-dn")
    end

    it "prefers the USDZ extension-derived type over the generic ZIP magic-byte detection" do
      expect(Marcel::MimeType.for(name: "model.usdz")).to eq("model/vnd.usdz+zip")
    end
  end
end
