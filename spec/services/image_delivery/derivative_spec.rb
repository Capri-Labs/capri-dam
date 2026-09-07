require "rails_helper"

RSpec.describe ImageDelivery::Derivative do
  let(:workspace) { Rails.root.join("tmp/derivative_spec") }
  let(:source) { workspace.join("source.jpg").to_s }

  # A noisy gradient rather than a flat colour: flat images compress
  # unrealistically well in every format and would prove nothing about whether
  # the encoder actually ran.
  def write_source(geometry: "800x600", quality: 92, path: source)
    FileUtils.mkdir_p(File.dirname(path))
    system("magick", "-size", geometry, "plasma:fractal", "-quality", quality.to_s, path,
           out: File::NULL, err: File::NULL)
    path
  end

  def fetch(format: "avif", path: source)
    described_class.fetch(
      source_path: path,
      format: format,
      content_type: ImageDelivery::FormatNegotiator::FORMATS[format],
    )
  end

  before { FileUtils.mkdir_p(workspace) }

  after do
    FileUtils.rm_rf(workspace)
    FileUtils.rm_rf(Rails.root.join(described_class::CACHE_ROOT))
  end

  describe "transcoding" do
    it "produces a real AVIF that is materially smaller than the source" do
      write_source
      result = fetch

      expect(result).not_to be_nil
      expect(result.content_type).to eq("image/avif")
      expect(File.size(result.path)).to be < File.size(source)

      identified = `magick identify -format '%m %wx%h' #{Shellwords.escape(result.path)}`
      expect(identified).to eq("AVIF 800x600")
    end

    it "produces a real WebP" do
      write_source
      result = fetch(format: "webp")

      identified = `magick identify -format '%m %wx%h' #{Shellwords.escape(result.path)}`
      expect(identified).to eq("WEBP 800x600")
    end

    it "preserves the source's pixel dimensions" do
      write_source(geometry: "1024x256")

      identified = `magick identify -format '%wx%h' #{Shellwords.escape(fetch.path)}`
      expect(identified).to eq("1024x256")
    end
  end

  describe "caching" do
    it "reuses the derivative on a second request instead of re-encoding" do
      write_source
      first = fetch
      mtime = File.mtime(first.path)

      second = fetch

      expect(second.path).to eq(first.path)
      expect(File.mtime(second.path)).to eq(mtime)
    end

    it "keys each format separately" do
      write_source

      expect(fetch(format: "avif").path).not_to eq(fetch(format: "webp").path)
    end

    it "misses the cache once the source changes" do
      write_source
      original = fetch.path

      # A re-upload replaces the bytes; the derivative for the old ones must
      # not be served for the new image.
      sleep 1.1
      write_source(geometry: "640x480")

      expect(fetch.path).not_to eq(original)
    end
  end

  describe "refusing to make things worse" do
    it "returns nil when the encode is not smaller than the source" do
      # Already-minimal source: re-encoding cannot pay for the format's
      # overhead, and serving a *larger* file would be a pessimisation
      # disguised as a modernisation.
      tiny = workspace.join("tiny.jpg").to_s
      FileUtils.mkdir_p(File.dirname(tiny))
      system("magick", "-size", "8x8", "xc:white", "-quality", "20", tiny,
             out: File::NULL, err: File::NULL)

      expect(fetch(path: tiny)).to be_nil
    end

    it "caches nothing when it declines to transcode" do
      tiny = workspace.join("tiny.jpg").to_s
      system("magick", "-size", "8x8", "xc:white", "-quality", "20", tiny,
             out: File::NULL, err: File::NULL)
      fetch(path: tiny)

      cache_root = Rails.root.join(described_class::CACHE_ROOT)
      leftovers = Dir.glob(cache_root.join("**/*")).select { |f| File.file?(f) }
      expect(leftovers).to be_empty
    end

    it "leaves no temp files behind" do
      write_source
      fetch

      cache_root = Rails.root.join(described_class::CACHE_ROOT)
      expect(Dir.glob(cache_root.join("**/*.tmp"))).to be_empty
    end
  end

  describe "degrading instead of failing" do
    it "returns nil for a source that is not an image" do
      broken = workspace.join("broken.jpg").to_s
      File.binwrite(broken, "this is not a JPEG")

      expect { expect(fetch(path: broken)).to be_nil }.not_to raise_error
    end

    it "returns nil for a missing source" do
      expect(fetch(path: workspace.join("absent.jpg").to_s)).to be_nil
    end

    it "returns nil for an empty source" do
      empty = workspace.join("empty.jpg").to_s
      FileUtils.touch(empty)

      expect(fetch(path: empty)).to be_nil
    end

    it "does not transcode a source above the size ceiling" do
      write_source
      stub_const("#{described_class}::MAX_SOURCE_BYTES", 10)

      # Transcoding a very large original inline on a request thread costs more
      # than the bytes it saves.
      expect(fetch).to be_nil
    end

    it "returns nil rather than raising when the encoder fails" do
      write_source
      allow(MiniMagick::Image).to receive(:open).and_raise(StandardError, "delegate missing")

      expect { expect(fetch).to be_nil }.not_to raise_error
    end
  end
end
