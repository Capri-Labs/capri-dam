require "rails_helper"

RSpec.describe ImageDelivery::FormatNegotiator do
  subject(:negotiated) do
    described_class.new(
      source_content_type: source_content_type,
      accept_header: accept_header,
      requested_format: requested_format,
    ).call
  end

  let(:source_content_type) { "image/jpeg" }
  let(:accept_header) { "image/avif,image/webp,image/apng,*/*" }
  let(:requested_format) { nil }

  def enable(*formats)
    create(:cdn_configuration,
           provider: "fastly",
           is_active: true,
           settings: { "image_optimizer_formats" => formats })
  end

  describe "the administrator's allow-list" do
    it "transcodes nothing when no CDN configuration is active" do
      expect(negotiated).to be_nil
    end

    it "transcodes nothing when an active configuration enables no formats" do
      enable

      expect(negotiated).to be_nil
    end

    it "ignores the allow-list on an inactive configuration" do
      create(:cdn_configuration, provider: "akamai", is_active: false,
                                 settings: { "image_optimizer_formats" => %w[avif] })

      expect(negotiated).to be_nil
    end

    it "serves a format once the administrator enables it" do
      enable("avif")

      expect(negotiated.format).to eq("avif")
      expect(negotiated.content_type).to eq("image/avif")
    end

    it "will not serve a format the administrator left disabled" do
      enable("webp")

      # The browser accepts AVIF, but it has not been switched on.
      expect(negotiated.format).to eq("webp")
    end

    it "ignores an unrecognised format sitting in the settings" do
      enable("jxl", "avif")

      expect(negotiated.format).to eq("avif")
    end

    it "falls back to the original when the settings cannot be read" do
      enable("avif")
      allow(CdnConfiguration).to receive(:find_by).and_raise(StandardError, "decrypt failed")

      # A delivery request must not fail because of a settings problem.
      expect(negotiated).to be_nil
    end
  end

  describe "client capability" do
    before { enable("avif", "webp") }

    it "prefers AVIF when the client accepts both" do
      expect(negotiated.format).to eq("avif")
    end

    context "when the client accepts only WebP" do
      let(:accept_header) { "image/webp,image/apng,image/*,*/*;q=0.8" }

      it "falls back to WebP rather than sending an undecodable AVIF" do
        expect(negotiated.format).to eq("webp")
      end
    end

    context "when the client accepts neither" do
      let(:accept_header) { "image/png,image/*,*/*;q=0.8" }

      it "serves the original" do
        # `image/*` is not evidence: it predates both formats and every browser
        # sends it regardless of what it can actually decode.
        expect(negotiated).to be_nil
      end
    end

    context "when there is no Accept header at all" do
      let(:accept_header) { nil }

      it "serves the original" do
        expect(negotiated).to be_nil
      end
    end

    context "when the client sends only a wildcard" do
      let(:accept_header) { "*/*" }

      it "serves the original" do
        expect(negotiated).to be_nil
      end
    end
  end

  describe "explicit ?output= override" do
    before { enable("avif") }

    let(:accept_header) { "*/*" }
    let(:requested_format) { "avif" }

    it "is honoured without an Accept header, for non-browser callers" do
      expect(negotiated.format).to eq("avif")
    end

    it "is still subject to the allow-list" do
      # An explicit request is not permission to bypass the administrator.
      expect(
        described_class.new(source_content_type: "image/jpeg",
                            accept_header: "*/*",
                            requested_format: "webp").call,
      ).to be_nil
    end

    it "ignores a format this pipeline does not produce" do
      expect(
        described_class.new(source_content_type: "image/jpeg",
                            accept_header: "image/avif",
                            requested_format: "png").call,
      ).to be_nil
    end

    it "is case-insensitive" do
      expect(
        described_class.new(source_content_type: "image/jpeg",
                            accept_header: "*/*",
                            requested_format: "AVIF").call.format,
      ).to eq("avif")
    end
  end

  describe "which sources are worth re-encoding" do
    before { enable("avif", "webp") }

    %w[image/jpeg image/jpg image/pjpeg image/png].each do |type|
      it "transcodes #{type}" do
        expect(
          described_class.new(source_content_type: type, accept_header: accept_header).call,
        ).not_to be_nil
      end
    end

    it "leaves SVG alone" do
      expect(
        described_class.new(source_content_type: "image/svg+xml", accept_header: accept_header).call,
      ).to be_nil
    end

    it "leaves GIF alone because it may be animated" do
      # A single-frame AVIF would silently truncate an animation to its first
      # frame, which looks like a broken image rather than a smaller one.
      expect(
        described_class.new(source_content_type: "image/gif", accept_header: accept_header).call,
      ).to be_nil
    end

    it "does not re-encode something already in a modern format" do
      expect(
        described_class.new(source_content_type: "image/avif", accept_header: accept_header).call,
      ).to be_nil
      expect(
        described_class.new(source_content_type: "image/webp", accept_header: accept_header).call,
      ).to be_nil
    end

    it "leaves video alone" do
      expect(
        described_class.new(source_content_type: "video/mp4", accept_header: accept_header).call,
      ).to be_nil
    end

    it "tolerates a content type carrying parameters" do
      expect(
        described_class.new(source_content_type: "image/jpeg; charset=binary",
                            accept_header: accept_header).call.format,
      ).to eq("avif")
    end

    it "tolerates a blank content type" do
      expect(
        described_class.new(source_content_type: nil, accept_header: accept_header).call,
      ).to be_nil
    end
  end
end
