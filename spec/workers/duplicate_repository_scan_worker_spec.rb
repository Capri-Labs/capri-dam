require "rails_helper"

RSpec.describe DuplicateRepositoryScanWorker, type: :worker do
  subject(:worker) { described_class.new }

  let(:checksum_a) { "aaaa" * 16 }
  let(:checksum_b) { "bbbb" * 16 }

  before do
    Setting.set("duplicate_manager_enabled", true)
    Setting.set("duplicate_manager_scan_status", "idle")
  end

  # ---------------------------------------------------------------------------
  # Guard: detection disabled
  # ---------------------------------------------------------------------------
  describe "when detection is disabled" do
    before { Setting.set("duplicate_manager_enabled", false) }

    it "returns immediately without creating groups" do
      expect { worker.perform }.not_to change(DuplicateGroup, :count)
    end

    it "does not change the scan status" do
      worker.perform
      expect(Setting.get("duplicate_manager_scan_status")).to eq("idle")
    end
  end

  # ---------------------------------------------------------------------------
  # Guard: scan already running
  # ---------------------------------------------------------------------------
  describe "when a scan is already running" do
    before do
      Setting.set("duplicate_manager_scan_status", "running")
      Setting.set("duplicate_manager_scan_progress", { processed: 1, total: 2, updated_at: Time.current.iso8601 })
    end

    it "returns immediately without creating groups" do
      expect { worker.perform }.not_to change(DuplicateGroup, :count)
    end

    it "does not change the scan status away from 'running'" do
      worker.perform
      expect(Setting.get("duplicate_manager_scan_status")).to eq("running")
    end
  end

  # ---------------------------------------------------------------------------
  # Guard: stale "running" lock is reclaimed (worker crashed mid-scan)
  # ---------------------------------------------------------------------------
  describe "when a previous scan is stuck 'running' with stale progress" do
    let(:stale_time) { (DuplicateRepositoryScanWorker::STALE_AFTER + 5.minutes).ago.iso8601 }

    before do
      Setting.set("duplicate_manager_scan_status", "running")
      Setting.set("duplicate_manager_scan_progress", { processed: 3, total: 10, updated_at: stale_time })
    end

    it "no longer reports the scan as running" do
      expect(DuplicateRepositoryScanWorker.scan_running?).to be(false)
    end

    it "reclaims the lock by marking the stale scan as 'failed'" do
      DuplicateRepositoryScanWorker.scan_running?
      expect(Setting.get("duplicate_manager_scan_status")).to eq("failed")
      expect(Setting.get("duplicate_manager_scan_progress")[:error]).to match(/stalled/i)
    end

    it "allows a fresh scan to run instead of being skipped" do
      expect { worker.perform }.not_to raise_error
      expect(Setting.get("duplicate_manager_scan_status")).to eq("completed")
    end

    it "treats a 'running' status with no progress payload at all as stale too" do
      Setting.set("duplicate_manager_scan_progress", nil)
      expect(DuplicateRepositoryScanWorker.scan_running?).to be(false)
    end
  end

  # ---------------------------------------------------------------------------
  # No duplicates in the repository
  # ---------------------------------------------------------------------------
  describe "when there are no duplicate checksums" do
    let!(:asset_a)   { create(:asset) }
    let!(:version_a) { create(:asset_version, asset: asset_a, properties: { "checksum_sha256" => checksum_a }) }

    it "does not create any DuplicateGroup records" do
      expect { worker.perform }.not_to change(DuplicateGroup, :count)
    end

    it "marks scan as completed" do
      worker.perform
      expect(Setting.get("duplicate_manager_scan_status")).to eq("completed")
    end

    it "records last_scan_at" do
      worker.perform
      expect(Setting.get("duplicate_manager_last_scan_at")).to be_present
    end
  end

  # ---------------------------------------------------------------------------
  # Version-awareness: same asset, multiple versions with same checksum
  # ---------------------------------------------------------------------------
  describe "version-awareness rule" do
    context "when the SAME asset has multiple versions sharing a checksum" do
      let!(:asset)     { create(:asset) }
      let!(:version_1) { create(:asset_version, asset: asset, version_number: 1, properties: { "checksum_sha256" => checksum_a }) }
      let!(:version_2) { create(:asset_version, asset: asset, version_number: 2, properties: { "checksum_sha256" => checksum_a }) }

      it "does NOT create a duplicate group (same asset ID — just version history)" do
        expect { worker.perform }.not_to change(DuplicateGroup, :count)
      end
    end

    context "when DIFFERENT assets share a checksum" do
      let!(:asset_1)   { create(:asset) }
      let!(:asset_2)   { create(:asset) }
      let!(:version_1) { create(:asset_version, asset: asset_1, properties: { "checksum_sha256" => checksum_a }) }
      let!(:version_2) { create(:asset_version, asset: asset_2, properties: { "checksum_sha256" => checksum_a }) }

      it "creates a duplicate group" do
        expect { worker.perform }.to change(DuplicateGroup, :count).by(1)
      end
    end

    context "when an asset has 3 versions, two with checksum_a, and a second asset also has checksum_a" do
      # Asset A (v1=checksum_a, v2=checksum_b, v3=checksum_a) + Asset B (v1=checksum_a)
      # → checksum_a appears for 2 distinct assets → 1 duplicate group
      # → checksum_b appears for 1 asset → NOT a duplicate
      let!(:asset_a)   { create(:asset) }
      let!(:asset_b)   { create(:asset) }
      let!(:va1) { create(:asset_version, asset: asset_a, version_number: 1, properties: { "checksum_sha256" => checksum_a }) }
      let!(:va2) { create(:asset_version, asset: asset_a, version_number: 2, properties: { "checksum_sha256" => checksum_b }) }
      let!(:va3) { create(:asset_version, asset: asset_a, version_number: 3, properties: { "checksum_sha256" => checksum_a }) }
      let!(:vb1) { create(:asset_version, asset: asset_b, version_number: 1, properties: { "checksum_sha256" => checksum_a }) }

      it "creates exactly one group (for checksum_a only)" do
        expect { worker.perform }.to change(DuplicateGroup, :count).by(1)
        expect(DuplicateGroup.last.checksum).to eq(checksum_a)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Soft-deleted assets excluded
  # ---------------------------------------------------------------------------
  describe "soft-deleted asset exclusion" do
    let!(:asset_1)   { create(:asset) }
    let!(:asset_2)   { create(:asset, :trashed) }
    let!(:version_1) { create(:asset_version, asset: asset_1, properties: { "checksum_sha256" => checksum_a }) }
    let!(:version_2) { create(:asset_version, asset: asset_2, properties: { "checksum_sha256" => checksum_a }) }

    it "ignores soft-deleted assets" do
      expect { worker.perform }.not_to change(DuplicateGroup, :count)
    end
  end

  # ---------------------------------------------------------------------------
  # Group creation and membership
  # ---------------------------------------------------------------------------
  describe "group creation" do
    let!(:asset_1) { create(:asset) }
    let!(:asset_2) { create(:asset) }
    let!(:asset_3) { create(:asset) }
    let!(:v1) { create(:asset_version, asset: asset_1, properties: { "checksum_sha256" => checksum_a }) }
    let!(:v2) { create(:asset_version, asset: asset_2, properties: { "checksum_sha256" => checksum_a }) }
    let!(:v3) { create(:asset_version, asset: asset_3, properties: { "checksum_sha256" => checksum_a }) }

    it "creates one group per unique checksum" do
      expect { worker.perform }.to change(DuplicateGroup, :count).by(1)
    end

    it "registers all distinct assets as members" do
      worker.perform
      group = DuplicateGroup.last
      expect(group.duplicate_group_assets.count).to eq(3)
      expect(group.duplicate_group_assets.map(&:asset_id)).to contain_exactly(
        asset_1.id, asset_2.id, asset_3.id
      )
    end

    it "sets total_count correctly" do
      worker.perform
      expect(DuplicateGroup.last.total_count).to eq(3)
    end

    it "marks the oldest asset as is_original" do
      worker.perform
      group = DuplicateGroup.last
      original = group.duplicate_group_assets.find_by(is_original: true)
      oldest   = [ asset_1, asset_2, asset_3 ].min_by(&:created_at)
      expect(original.asset_id).to eq(oldest.id)
    end
  end

  # ---------------------------------------------------------------------------
  # Multiple checksums
  # ---------------------------------------------------------------------------
  describe "multiple duplicate checksums" do
    let!(:a1) { create(:asset) }
    let!(:a2) { create(:asset) }
    let!(:a3) { create(:asset) }
    let!(:a4) { create(:asset) }

    before do
      create(:asset_version, asset: a1, properties: { "checksum_sha256" => checksum_a })
      create(:asset_version, asset: a2, properties: { "checksum_sha256" => checksum_a })
      create(:asset_version, asset: a3, properties: { "checksum_sha256" => checksum_b })
      create(:asset_version, asset: a4, properties: { "checksum_sha256" => checksum_b })
    end

    it "creates one group per duplicated checksum" do
      expect { worker.perform }.to change(DuplicateGroup, :count).by(2)
    end

    it "assigns the correct members to each group" do
      worker.perform
      group_a = DuplicateGroup.find_by(checksum: checksum_a)
      group_b = DuplicateGroup.find_by(checksum: checksum_b)

      expect(group_a.duplicate_group_assets.map(&:asset_id)).to contain_exactly(a1.id, a2.id)
      expect(group_b.duplicate_group_assets.map(&:asset_id)).to contain_exactly(a3.id, a4.id)
    end
  end

  # ---------------------------------------------------------------------------
  # Idempotency: running the scan twice
  # ---------------------------------------------------------------------------
  describe "idempotency" do
    let!(:a1) { create(:asset) }
    let!(:a2) { create(:asset) }

    before do
      create(:asset_version, asset: a1, properties: { "checksum_sha256" => checksum_a })
      create(:asset_version, asset: a2, properties: { "checksum_sha256" => checksum_a })
    end

    it "does not create duplicate groups when run twice" do
      worker.perform
      Setting.set("duplicate_manager_scan_status", "idle")

      expect { worker.perform }.not_to change(DuplicateGroup, :count)
    end

    it "does not add duplicate members on second run" do
      worker.perform
      Setting.set("duplicate_manager_scan_status", "idle")
      worker.perform

      group = DuplicateGroup.find_by(checksum: checksum_a)
      expect(group.duplicate_group_assets.count).to eq(2)
    end
  end

  # ---------------------------------------------------------------------------
  # Skips resolved/dismissed groups
  # ---------------------------------------------------------------------------
  describe "existing resolved groups" do
    let!(:a1) { create(:asset) }
    let!(:a2) { create(:asset) }

    before do
      create(:asset_version, asset: a1, properties: { "checksum_sha256" => checksum_a })
      create(:asset_version, asset: a2, properties: { "checksum_sha256" => checksum_a })
    end

    it "creates a new pending group even when a resolved group exists for the same checksum" do
      # Pre-existing resolved group (user already resolved it once)
      create(:duplicate_group, checksum: checksum_a, status: "resolved")

      expect { worker.perform }.to change(DuplicateGroup.pending, :count).by(1)
    end
  end

  # ---------------------------------------------------------------------------
  # Status lifecycle
  # ---------------------------------------------------------------------------
  describe "scan status lifecycle" do
    it "sets status to 'running' when it starts" do
      # We can't easily test mid-execution, but we can verify the completed state
      worker.perform
      expect(Setting.get("duplicate_manager_scan_status")).to eq("completed")
    end

    it "sets last_scan_at on completion" do
      worker.perform
      expect(Setting.get("duplicate_manager_last_scan_at")).to be_present
    end

    it "sets status to 'failed' and re-raises when an error occurs" do
      allow(ActiveRecord::Base.connection).to receive(:exec_query).and_raise(RuntimeError, "db error")

      expect { worker.perform }.to raise_error(RuntimeError, "db error")
      expect(Setting.get("duplicate_manager_scan_status")).to eq("failed")
    end
  end

  # ---------------------------------------------------------------------------
  # Progress tracking
  # ---------------------------------------------------------------------------
  describe "progress tracking" do
    let!(:a1) { create(:asset) }
    let!(:a2) { create(:asset) }
    let!(:a3) { create(:asset) }
    let!(:a4) { create(:asset) }

    before do
      create(:asset_version, asset: a1, properties: { "checksum_sha256" => checksum_a })
      create(:asset_version, asset: a2, properties: { "checksum_sha256" => checksum_a })
      create(:asset_version, asset: a3, properties: { "checksum_sha256" => checksum_b })
      create(:asset_version, asset: a4, properties: { "checksum_sha256" => checksum_b })
    end

    it "stores progress in settings" do
      worker.perform
      progress = Setting.get("duplicate_manager_scan_progress")
      expect(progress).to be_a(Hash)
      expect(progress[:processed].to_i).to eq(2)
      expect(progress[:total].to_i).to eq(2)
    end
  end

  # ---------------------------------------------------------------------------
  # Sidekiq configuration
  # ---------------------------------------------------------------------------
  describe "Sidekiq configuration" do
    it "uses the duplicate_detection queue" do
      expect(described_class.get_sidekiq_options["queue"]).to eq("duplicate_detection")
    end
  end

  describe 'private edge cases' do
    it 'returns early when a checksum group has fewer than two asset ids' do
      expect do
        worker.send(:process_checksum_group, checksum_a, [ 'only-one' ])
      end.not_to change(DuplicateGroup, :count)
    end

    it 'leaves duplicate groups untouched when no oldest asset can be found' do
      group = create(:duplicate_group, checksum: checksum_a, total_count: 0)

      expect { worker.send(:mark_original, group) }.not_to raise_error
      expect(group.duplicate_group_assets).to be_empty
    end

    it 'logs failures without assuming a backtrace is present' do
      error = RuntimeError.new('db error')
      error.set_backtrace(nil)
      allow(worker).to receive(:fetch_duplicate_checksums).and_raise(error)
      allow(Rails.logger).to receive(:error)

      expect { worker.perform }.to raise_error(RuntimeError, 'db error')
      expect(Rails.logger).to have_received(:error).with(/Scan failed: RuntimeError: db error/)
    end
  end
end
