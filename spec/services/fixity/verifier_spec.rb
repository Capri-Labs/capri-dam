# frozen_string_literal: true

require "rails_helper"

RSpec.describe Fixity::Verifier do
  let(:asset)   { create(:asset) }
  let(:content) { "the bytes that were ingested" }
  let(:digest)  { Digest::SHA256.hexdigest(content) }
  let(:storage_path) { "fixity-spec/#{SecureRandom.uuid}.bin" }
  let(:root)    { StorageAdapters::LocalStorageAdapter::ROOT.call }

  def build_version(properties)
    create(:asset_version, asset: asset, properties: properties)
  end

  def write_object(bytes)
    full = root.join(storage_path)
    FileUtils.mkdir_p(full.dirname)
    File.binwrite(full, bytes)
    full
  end

  before do
    StorageManager.reset_active_adapter!
    allow(StorageManager).to receive(:active_adapter).and_return(StorageAdapters::LocalStorageAdapter.new({}))
  end

  after do
    FileUtils.rm_rf(root.join("fixity-spec"))
    StorageManager.reset_active_adapter!
  end

  describe "when the bytes are intact" do
    it "records a passing check and caches the verdict on the version" do
      write_object(content)
      version = build_version("checksum_sha256" => digest, "storage_path" => storage_path)

      result = described_class.call(version)

      expect(result).to be_passed
      expect(result.check.actual_checksum).to eq(digest)
      expect(result.check.byte_size).to eq(content.bytesize)
      expect(version.reload.fixity_status).to eq("passed")
      expect(version.last_fixity_check_at).to be_present
    end

    it "does not touch updated_at, because an audit is not an edit" do
      write_object(content)
      version = build_version("checksum_sha256" => digest, "storage_path" => storage_path)
      before_update = version.updated_at

      described_class.call(version)

      expect(version.reload.updated_at).to be_within(1.second).of(before_update)
    end

    it "hashes correctly across chunk boundaries" do
      big = SecureRandom.bytes(Fixity::Verifier::CHUNK_SIZE + 1024)
      write_object(big)
      version = build_version(
        "checksum_sha256" => Digest::SHA256.hexdigest(big),
        "storage_path" => storage_path,
      )

      expect(described_class.call(version)).to be_passed
    end
  end

  describe "when the bytes have changed" do
    it "records a failure with both digests" do
      write_object("something else entirely")
      version = build_version("checksum_sha256" => digest, "storage_path" => storage_path)

      result = described_class.call(version)

      expect(result.status).to eq("failed")
      expect(result.check.expected_checksum).to eq(digest)
      expect(result.check.actual_checksum).not_to eq(digest)
      expect(version.reload.fixity_status).to eq("failed")
    end
  end

  describe "when the object is gone" do
    it "records missing rather than failed" do
      version = build_version("checksum_sha256" => digest, "storage_path" => storage_path)

      result = described_class.call(version)

      expect(result.status).to eq("missing")
      expect(result.check.actual_checksum).to be_nil
    end
  end

  describe "when storage cannot answer" do
    it "records unreadable, so a network fault never raises a corruption alarm" do
      write_object(content)
      version = build_version("checksum_sha256" => digest, "storage_path" => storage_path)
      allow(File).to receive(:open).and_raise(Errno::ECONNRESET)

      result = described_class.call(version)

      expect(result.status).to eq("unreadable")
      expect(result.check.error_message).to include("ECONNRESET")
      expect(FixityCheck.last).not_to be_conclusive
    end
  end

  describe "when there is nothing to compare against" do
    it "returns nil for a version with no checksum" do
      version = build_version("storage_path" => storage_path)

      expect(described_class.call(version)).to be_nil
      expect(FixityCheck.count).to eq(0)
    end

    it "returns nil for a version with no storage path" do
      version = build_version("checksum_sha256" => digest)

      expect(described_class.call(version)).to be_nil
      expect(FixityCheck.count).to eq(0)
    end
  end
end
