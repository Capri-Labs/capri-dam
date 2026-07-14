require "rails_helper"
require "zip"

RSpec.describe AssetDownloadWorker, type: :worker do
  let(:user) { create(:user) }
  let(:cleanup_paths) { [] }

  # Writes a real file under storage/dam and returns the asset it belongs to,
  # mirroring how the upload pipeline stamps `storage_path` onto the active
  # version's properties (see Api::V1::AssetsController / AssetProcessorWorker).
  def asset_with_file(folder: nil, title: "Asset", filename: "file.txt", body: "hello world")
    asset = create(:asset, user: user, folder: folder, title: title)
    storage_path = "#{asset.uuid}/#{filename}"
    full_path = StorageAdapters::LocalStorageAdapter::ROOT.call.join(storage_path)
    FileUtils.mkdir_p(full_path.dirname)
    File.write(full_path, body)
    cleanup_paths << full_path.dirname
    version = create(:asset_version, asset: asset, version_number: 1,
                                      properties: { "storage_path" => storage_path, "original_filename" => filename })
    asset.update!(active_version_id: version.id)
    asset
  end

  def zip_entries(download)
    tmp_path = Rails.root.join("tmp", "spec_download_#{download.id}.zip")
    download.zip_file.blob.open { |f| FileUtils.cp(f.path, tmp_path) }
    cleanup_paths << tmp_path
    Zip::File.open(tmp_path.to_s) { |zip| zip.entries.map(&:name) }
  end

  after { cleanup_paths.each { |p| FileUtils.rm_rf(p) } }

  it "zips a flat selection of assets, attaches the archive, and notifies the user" do
    asset = asset_with_file(title: "Report")
    download = create(:asset_download, user: user, asset_ids: [ asset.id ], folder_ids: [], total_items: 1)

    expect {
      described_class.new.perform(download.id)
    }.to change { user.notifications.count }.by(1)
      .and change { user.inbox_messages.count }.by(1)

    download.reload
    expect(download).to be_completed
    expect(download.zip_file).to be_attached
    expect(download.processed_items).to eq(1)
    expect(download.file_count).to eq(1)
    expect(download.byte_size).to be > 0
    expect(download.expires_at).to be_within(1.minute).of(7.days.from_now)
    expect(user.notifications.last.title).to match(/download ready/i)
    expect(user.inbox_messages.last.body_html).to include("/api/v1/asset_downloads/#{download.id}/download")

    expect(zip_entries(download)).to contain_exactly("file.txt")
  end

  it "recursively zips a folder, nesting subfolder assets under their folder path" do
    root  = create(:folder, user: user, name: "Root")
    child = create(:folder, user: user, parent: root, name: "Child")
    top_asset  = asset_with_file(folder: root, title: "TopAsset", filename: "top.txt", body: "top")
    deep_asset = asset_with_file(folder: child, title: "DeepAsset", filename: "deep.txt", body: "deep")

    download = create(:asset_download, user: user, folder_ids: [ root.id ], asset_ids: [], total_items: 2)

    described_class.new.perform(download.id)

    download.reload
    expect(download).to be_completed
    entries = zip_entries(download)
    expect(entries).to contain_exactly("Root/top.txt", "Root/Child/deep.txt")
    expect([ top_asset, deep_asset ]).to all(satisfy { |a| a.reload.deleted_at.nil? }) # originals untouched
  end

  it "resolves a filename collision by appending (2), (3), etc." do
    folder = create(:folder, user: user, name: "Shared")
    asset_with_file(folder: folder, title: "One", filename: "same.txt", body: "one")
    asset_with_file(folder: folder, title: "Two", filename: "same.txt", body: "two")

    download = create(:asset_download, user: user, folder_ids: [ folder.id ], asset_ids: [], total_items: 2)
    described_class.new.perform(download.id)

    expect(zip_entries(download.reload)).to contain_exactly("Shared/same.txt", "Shared/same (2).txt")
  end

  it "skips an asset with no storage_path on its active version but still completes" do
    asset = create(:asset, user: user, title: "NoFile")
    version = create(:asset_version, asset: asset, version_number: 1, properties: {})
    asset.update!(active_version_id: version.id)

    download = create(:asset_download, user: user, asset_ids: [ asset.id ], folder_ids: [], total_items: 1)
    described_class.new.perform(download.id)

    download.reload
    expect(download).to be_completed
    expect(zip_entries(download)).to eq([])
  end

  it "reads the file from local disk even when the Settings-based active_storage_provider drifts out of sync with the real active StorageBackend" do
    # Regression test: AssetDownloadWorker previously resolved files via
    # StorageManager.active_adapter, which is built from the
    # `active_storage_provider` Setting — a separate, independently
    # editable value from the StorageBackend row actually flagged
    # `active: true` (the one AssetProcessorWorker used to physically write
    # the file at upload time). When these drift apart (e.g. Settings says
    # "aws" but the real active backend, and the physical file, are local),
    # every asset was silently skipped and the ZIP came out with no images.
    Setting.set("active_storage_provider", "aws")
    StorageManager.reset_active_adapter!

    asset = asset_with_file(title: "DriftedSettings", filename: "drift.txt", body: "still on disk")
    download = create(:asset_download, user: user, asset_ids: [ asset.id ], folder_ids: [], total_items: 1)

    described_class.new.perform(download.id)

    download.reload
    expect(download).to be_completed
    expect(zip_entries(download)).to contain_exactly("drift.txt")
  ensure
    Setting.set("active_storage_provider", nil)
    StorageManager.reset_active_adapter!
  end

  it "is idempotent for an already-completed download" do
    download = create(:asset_download, :completed, user: user)
    expect { described_class.new.perform(download.id) }.not_to change { user.notifications.count }
  end

  it "returns early when the download no longer exists" do
    expect { described_class.new.perform(0) }.not_to raise_error
  end

  it "marks the download failed and notifies on error, then re-raises" do
    download = create(:asset_download, user: user, asset_ids: [], folder_ids: [])
    allow_any_instance_of(described_class).to receive(:collect_entries).and_raise(StandardError.new("boom"))

    expect { described_class.new.perform(download.id) }.to raise_error(StandardError, "boom")

    download.reload
    expect(download).to be_failed
    expect(download.error_message).to eq("boom")
    expect(user.notifications.last.title).to match(/download failed/i)
  end
end
