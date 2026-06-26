require "rails_helper"

RSpec.describe BinPurgeWorker, type: :worker do
  let(:admin)     { create(:user, :admin) }
  let(:non_admin) { create(:user) }

  # ── Shared helpers ──────────────────────────────────────────────────────────

  def trashed_asset_aged(days, **attrs)
    create(:asset, :trashed, deleted_at: days.days.ago, **attrs)
  end

  def fresh_trashed_asset(**attrs)
    create(:asset, :trashed, deleted_at: 1.day.ago, **attrs)
  end

  def expired_trashed_folder(days = 35)
    create(:folder, deleted_at: days.days.ago)
  end

  before do
    # Clean up any leftover Settings state
    Setting.where(key: BinPurgeWorker::LOCK_KEY).delete_all
    Setting.where(key: "bin_retention_days").delete_all
    Setting.where(key: "bin_workflow_behavior").delete_all
  end

  # ── Concurrency guard ───────────────────────────────────────────────────────

  describe "concurrency guard" do
    it "exits immediately when a purge is already running" do
      Setting.set(BinPurgeWorker::LOCK_KEY, "running")

      expect(BinPurgeService).not_to receive(:new)
      described_class.new.perform

      # Lock is not changed by the no-op
      expect(Setting.get(BinPurgeWorker::LOCK_KEY)).to eq("running")
    end

    it "proceeds when status is idle" do
      trashed_asset_aged(31)  # eligible
      expect { described_class.new.perform }.not_to raise_error
    end

    it "proceeds when status is completed from a previous run" do
      Setting.set(BinPurgeWorker::LOCK_KEY, "completed")
      trashed_asset_aged(31)
      expect { described_class.new.perform }.not_to raise_error
    end
  end

  # ── Retention policy loading ─────────────────────────────────────────────────

  describe "policy loading" do
    it "uses default retention_days (30) when not configured" do
      fresh_trashed_asset  # 1 day old — should NOT be deleted

      described_class.new.perform

      expect(Asset.trashed.count).to eq(1)
    end

    it "respects custom retention_days setting" do
      Setting.set("bin_retention_days", 7)
      asset = trashed_asset_aged(8)  # older than 7 days — should be deleted

      described_class.new.perform

      expect { asset.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "does NOT delete assets deleted within the retention window" do
      Setting.set("bin_retention_days", 30)
      asset = create(:asset, :trashed, deleted_at: 20.days.ago)

      described_class.new.perform

      expect { asset.reload }.not_to raise_error
    end
  end

  # ── Status lifecycle ─────────────────────────────────────────────────────────

  describe "status lifecycle" do
    it "sets status to 'running' then 'completed'" do
      described_class.new.perform
      expect(Setting.get(BinPurgeWorker::LOCK_KEY)).to eq("completed")
    end

    it "records last_ran_at after a successful run" do
      described_class.new.perform
      expect(Setting.get("bin_purge_last_ran_at")).to be_present
    end

    it "persists last_results after a successful run" do
      trashed_asset_aged(31)
      described_class.new.perform
      results = Setting.get("bin_purge_last_results")
      expect(results).to be_a(Hash)
      expect(results[:deleted] || results["deleted"]).to be_an(Integer)
    end

    it "sets status to 'failed' when an unhandled error occurs" do
      allow(BinPurgeService).to receive(:new).and_raise(StandardError, "DB down")

      expect { described_class.new.perform }.to raise_error(StandardError, "DB down")

      expect(Setting.get(BinPurgeWorker::LOCK_KEY)).to eq("failed")
    end

    it "stamps a scheduled triggered_by when not manually triggered" do
      described_class.new.perform

      triggered = Setting.get("bin_purge_triggered_by")
      expect(triggered).to be_a(Hash)
      expect(triggered[:source] || triggered["source"]).to eq("scheduled")
      expect(triggered[:user_name] || triggered["user_name"]).to eq("Scheduled (System)")
    end

    it "preserves a manual triggered_by stamp" do
      Setting.set("bin_purge_triggered_by", {
        user_id:      42,
        user_name:    "Alice Admin",
        source:       "manual",
        triggered_at: Time.current.iso8601,
      })

      described_class.new.perform

      triggered = Setting.get("bin_purge_triggered_by")
      expect(triggered[:source] || triggered["source"]).to eq("manual")
      expect(triggered[:user_name] || triggered["user_name"]).to eq("Alice Admin")
    end

    it "persists storage_reclaimed_bytes in last_results" do
      trashed_asset_aged(31)
      described_class.new.perform
      results = Setting.get("bin_purge_last_results")
      expect(results).to have_key(:storage_reclaimed_bytes).or have_key("storage_reclaimed_bytes")
    end
  end

  # ── Asset deletion ───────────────────────────────────────────────────────────

  describe "asset deletion" do
    it "permanently deletes expired assets" do
      asset = trashed_asset_aged(31)
      described_class.new.perform
      expect { asset.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "does not delete active (non-trashed) assets" do
      active_asset = create(:asset)
      described_class.new.perform
      expect { active_asset.reload }.not_to raise_error
    end

    it "deletes multiple expired assets" do
      a1 = trashed_asset_aged(31)
      a2 = trashed_asset_aged(45)
      a3 = trashed_asset_aged(60)
      described_class.new.perform
      [ a1, a2, a3 ].each do |a|
        expect { a.reload }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end

  # ── Workflow protection (behavior: skip) ─────────────────────────────────────

  describe "workflow protection — behavior: skip (default)" do
    it "skips assets with active workflow instances (default skip behavior)" do
      asset = trashed_asset_aged(31)
      create(:workflow_instance, asset: asset, status: "in_review")

      described_class.new.perform

      # Asset must remain — active workflow protects it
      expect { asset.reload }.not_to raise_error
    end

    it "deletes expired assets whose workflows are all completed" do
      asset = trashed_asset_aged(31)
      create(:workflow_instance, asset: asset, status: "completed")

      described_class.new.perform

      expect { asset.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "deletes expired assets with no workflow at all" do
      asset = trashed_asset_aged(31)

      described_class.new.perform

      expect { asset.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "records skipped items in last_results" do
      asset = trashed_asset_aged(31)
      create(:workflow_instance, asset: asset, status: "pending")

      described_class.new.perform

      results = Setting.get("bin_purge_last_results")
      skipped = (results[:skipped] || results["skipped"]).to_i
      expect(skipped).to eq(1)
    end
  end

  # ── Workflow force-terminate behavior ───────────────────────────────────────

  describe "workflow protection — behavior: force_terminate" do
    before { Setting.set("bin_workflow_behavior", "force_terminate") }

    it "terminates active workflows and deletes the asset" do
      asset = trashed_asset_aged(31)
      wf    = create(:workflow_instance, asset: asset, status: "in_review")

      described_class.new.perform

      expect { asset.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "cancels pending workflow tasks before deleting" do
      asset = trashed_asset_aged(31)
      wf    = create(:workflow_instance, asset: asset, status: "pending")
      task  = create(:workflow_task, workflow_instance: wf, status: "pending")

      described_class.new.perform

      expect { asset.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  # ── Reference cleanup ────────────────────────────────────────────────────────

  describe "reference cleanup" do
    it "removes DuplicateGroupAsset memberships before deletion" do
      asset = trashed_asset_aged(31)
      group = create(:duplicate_group)
      create(:duplicate_group_asset, asset: asset, duplicate_group: group)

      described_class.new.perform

      expect { asset.reload }.to raise_error(ActiveRecord::RecordNotFound)
      expect(DuplicateGroupAsset.where(asset_id: asset.id)).to be_empty
    end

    it "auto-resolves DuplicateGroup when only one member remains after purge" do
      asset1 = trashed_asset_aged(31)
      asset2 = create(:asset)  # active — stays
      group  = create(:duplicate_group, status: :pending)
      create(:duplicate_group_asset, asset: asset1, duplicate_group: group)
      create(:duplicate_group_asset, asset: asset2, duplicate_group: group)

      described_class.new.perform

      expect { asset1.reload }.to raise_error(ActiveRecord::RecordNotFound)
      expect(group.reload.status).to eq("resolved")
    end

    it "removes CollectionAsset records before deletion" do
      asset      = trashed_asset_aged(31)
      collection = create(:collection)
      create(:collection_asset, asset: asset, collection: collection)

      described_class.new.perform

      expect { asset.reload }.to raise_error(ActiveRecord::RecordNotFound)
      expect(CollectionAsset.where(asset_id: asset.id)).to be_empty
    end
  end

  # ── Folder deletion ──────────────────────────────────────────────────────────

  describe "folder deletion" do
    it "permanently deletes expired folders" do
      folder = expired_trashed_folder(35)
      described_class.new.perform
      expect { folder.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "skips folders that still contain active assets" do
      folder       = expired_trashed_folder(35)
      active_asset = create(:asset, folder: folder)

      described_class.new.perform

      expect { folder.reload }.not_to raise_error
    end

    it "skips folders that still contain active sub-folders" do
      parent       = expired_trashed_folder(35)
      active_child = create(:folder, parent_id: parent.id)

      described_class.new.perform

      expect { parent.reload }.not_to raise_error
    end
  end

  # ── Admin notification ───────────────────────────────────────────────────────

  describe "admin notifications" do
    it "sends a notification to admin users when items are deleted" do
      Setting.set("bin_purge_notify_admins", true)
      trashed_asset_aged(31)

      expect {
        described_class.new.perform
      }.to change { Notification.where(user: admin).count }.by(1)
    end

    it "does NOT notify when nothing notable happened" do
      # No expired items
      Setting.set("bin_purge_notify_admins", true)

      expect {
        described_class.new.perform
      }.not_to change { Notification.count }
    end

    it "does NOT notify when notify_admins is false" do
      Setting.set("bin_purge_notify_admins", false)
      trashed_asset_aged(31)

      expect {
        described_class.new.perform
      }.not_to change { Notification.count }
    end
  end

  # ── Error isolation ──────────────────────────────────────────────────────────

  describe "error isolation" do
    it "continues processing remaining items when one item fails" do
      # Create 3 expired assets
      asset1 = trashed_asset_aged(31, title: "Asset 1")
      asset2 = trashed_asset_aged(32, title: "Asset 2")
      asset3 = trashed_asset_aged(33, title: "Asset 3")

      # Make the DB destroy of asset2 fail — this is caught inside the service's
      # per-item rescue, so asset1 and asset3 still get purged.
      allow_any_instance_of(Asset).to receive(:destroy!).and_wrap_original do |m, *args|
        raise ActiveRecord::RecordNotDestroyed, "Simulated DB error" if m.receiver.id == asset2.id

        m.call(*args)
      end

      expect { described_class.new.perform }.not_to raise_error

      results = Setting.get("bin_purge_last_results")
      expect((results[:failed]  || results["failed"]).to_i).to  eq(1)
      expect((results[:deleted] || results["deleted"]).to_i).to eq(2)

      # asset1 & asset3 gone, asset2 survives
      expect { asset1.reload }.to raise_error(ActiveRecord::RecordNotFound)
      expect { asset3.reload }.to raise_error(ActiveRecord::RecordNotFound)
      expect { asset2.reload }.not_to raise_error
    end
  end

  # ── Sidekiq configuration ────────────────────────────────────────────────────

  describe "Sidekiq options" do
    it "uses the bin_purge queue" do
      expect(described_class.sidekiq_options["queue"]).to eq("bin_purge")
    end

    it "has zero retries" do
      expect(described_class.sidekiq_options["retry"]).to eq(0)
    end
  end
end
