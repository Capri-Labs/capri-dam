require "rails_helper"

RSpec.describe BinPurgeService do
  # ── Storage stub ─────────────────────────────────────────────────────────────
  # We stub StorageManager so no real files are touched, while verifying the
  # service calls delete with the right paths and accumulates reclaimed bytes.
  let(:storage_adapter) { instance_double("StorageAdapter", delete: true) }
  let(:storage_backend) { instance_double("StorageBackend") }

  before do
    allow(StorageBackend).to receive(:find_by).with(active: true).and_return(storage_backend)
    allow(StorageManager).to receive(:adapter_for).with(storage_backend).and_return(storage_adapter)
  end

  def expired_asset_with_versions(versions: 1, size_each: 1000, deleted_days: 40)
    asset = create(:asset, :trashed, deleted_at: deleted_days.days.ago)
    versions.times do |i|
      create(:asset_version, asset: asset, version_number: i + 1,
             properties: { "storage_path" => "store/path_#{asset.id}_v#{i + 1}.jpg", "size" => size_each })
    end
    asset
  end

  # ── Retention window ─────────────────────────────────────────────────────────

  describe "#call retention window" do
    it "deletes assets older than the retention window" do
      asset = expired_asset_with_versions(deleted_days: 40)
      result = described_class.new(retention_days: 30).call

      expect(result.deleted).to eq(1)
      expect { asset.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "leaves assets inside the retention window untouched" do
      asset = expired_asset_with_versions(deleted_days: 10)
      result = described_class.new(retention_days: 30).call

      expect(result.deleted).to eq(0)
      expect { asset.reload }.not_to raise_error
    end
  end

  # ── Version-aware storage deletion ───────────────────────────────────────────

  describe "asset version handling" do
    it "deletes the storage file for EVERY version of an asset" do
      asset = expired_asset_with_versions(versions: 3, size_each: 1000)

      expect(storage_adapter).to receive(:delete).exactly(3).times.and_return(true)

      described_class.new(retention_days: 30).call
    end

    it "accumulates storage_reclaimed_bytes across all versions" do
      expired_asset_with_versions(versions: 3, size_each: 1000)

      result = described_class.new(retention_days: 30).call

      expect(result.storage_reclaimed_bytes).to eq(3000)
    end

    it "sums reclaimed bytes across multiple assets" do
      expired_asset_with_versions(versions: 2, size_each: 500)  # 1000
      expired_asset_with_versions(versions: 1, size_each: 250)  # 250

      result = described_class.new(retention_days: 30).call

      expect(result.storage_reclaimed_bytes).to eq(1250)
      expect(result.deleted).to eq(2)
    end

    it "continues to delete the DB record even if a version storage delete fails" do
      asset = expired_asset_with_versions(versions: 2, size_each: 1000)
      allow(storage_adapter).to receive(:delete).and_raise(StandardError, "S3 timeout")

      result = described_class.new(retention_days: 30).call

      # Storage failure is non-fatal — asset row is still purged
      expect { asset.reload }.to raise_error(ActiveRecord::RecordNotFound)
      expect(result.deleted).to eq(1)
    end

    it "skips storage deletion when a version has no storage_path" do
      asset = create(:asset, :trashed, deleted_at: 40.days.ago)
      create(:asset_version, asset: asset, version_number: 1, properties: { "size" => 500 })

      expect(storage_adapter).not_to receive(:delete)

      described_class.new(retention_days: 30).call
    end
  end

  # ── Workflow protection ──────────────────────────────────────────────────────

  describe "active workflow protection (skip)" do
    it "skips assets with an active workflow and records the skip" do
      asset = expired_asset_with_versions
      create(:workflow_instance, asset: asset, status: "in_review")

      result = described_class.new(retention_days: 30, workflow_behavior: "skip").call

      expect(result.skipped).to eq(1)
      expect(result.deleted).to eq(0)
      expect { asset.reload }.not_to raise_error
      expect(result.skipped_items.first[:reason]).to eq("active_workflow")
    end

    it "deletes assets whose workflows are all completed" do
      asset = expired_asset_with_versions
      create(:workflow_instance, asset: asset, status: "completed")

      result = described_class.new(retention_days: 30, workflow_behavior: "skip").call

      expect(result.deleted).to eq(1)
    end
  end

  describe "active workflow force_terminate" do
    it "terminates active workflows then deletes the asset" do
      asset = expired_asset_with_versions
      wf    = create(:workflow_instance, asset: asset, status: "in_review")

      result = described_class.new(retention_days: 30, workflow_behavior: "force_terminate").call

      expect(result.deleted).to eq(1)
      expect { asset.reload }.to raise_error(ActiveRecord::RecordNotFound)
      expect { wf.reload }.to raise_error(ActiveRecord::RecordNotFound) # cascaded
    end

    it "records termination audit entries and cancels pending tasks" do
      asset = expired_asset_with_versions
      wf = create(:workflow_instance, asset: asset, status: "in_review")
      task = create(:workflow_task, workflow_instance: wf, status: "pending")

      described_class.new.send(:force_terminate_workflows!, [ wf ], asset)

      expect(wf.reload.status).to eq("terminated")
      expect(wf.audit_log.last).to include("action" => "terminated", "reason" => "asset_purged_from_bin", "asset_id" => asset.id)
      expect(task.reload.status).to eq("canceled")
    end
  end

  describe "duplicate-group cleanup" do
    it "resolves duplicate groups that have too few remaining members" do
      asset = expired_asset_with_versions
      group = create(:duplicate_group, status: "pending")
      create(:duplicate_group_asset, duplicate_group: group, asset: asset)

      result = described_class.new(retention_days: 30).call

      expect(result.deleted).to eq(1)
      expect(group.reload.status).to eq("resolved")
    end
  end

  describe "folder purge" do
    it "deletes expired trashed folders with no active children" do
      folder = create(:folder, :trashed, deleted_at: 40.days.ago)

      result = described_class.new(retention_days: 30).call

      expect(result.deleted).to eq(1)
      expect { folder.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "skips expired folders that still contain active children" do
      folder = create(:folder, :trashed, deleted_at: 40.days.ago)
      create(:asset, folder: folder, status: :ready)
      create(:folder, parent: folder)

      result = described_class.new(retention_days: 30).call

      expect(result.skipped).to eq(1)
      expect(result.skipped_items.first).to include(type: "folder", reason: "has_active_children")
      expect { folder.reload }.not_to raise_error
    end

    it "records folder purge failures and continues" do
      folder = create(:folder, :trashed, deleted_at: 40.days.ago)
      allow(folder).to receive(:destroy!).and_raise(StandardError, "locked")
      allow(Folder).to receive_message_chain(:trashed, :where, :order, :find_each).and_yield(folder)

      result = described_class.new(retention_days: 30).call

      expect(result.failed).to eq(1)
      expect(result.errors).to contain_exactly(hash_including(id: folder.id, type: "folder", title: folder.name, message: "locked"))
    end
  end

  describe "storage adapter loading" do
    it "returns nil without looking up an adapter when no backend is active" do
      allow(StorageBackend).to receive(:find_by).with(active: true).and_return(nil)

      service = described_class.new

      expect(service.send(:storage_adapter)).to be_nil
      expect(service.send(:storage_adapter)).to be_nil
      expect(StorageManager).not_to have_received(:adapter_for)
      expect(StorageBackend).to have_received(:find_by).once
    end
  end

  # ── Result shape ─────────────────────────────────────────────────────────────

  describe "result object" do
    it "exposes deleted, skipped, failed, storage_reclaimed_bytes" do
      expired_asset_with_versions
      result = described_class.new(retention_days: 30).call

      expect(result).to respond_to(:deleted, :skipped, :failed, :storage_reclaimed_bytes, :errors, :skipped_items)
    end
  end
end
