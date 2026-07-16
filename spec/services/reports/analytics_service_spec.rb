require 'rails_helper'

REAL_ASSET_EMBEDDING_CLASS = AssetEmbedding

RSpec.describe Reports::AnalyticsService, type: :service do
  include ActiveSupport::Testing::TimeHelpers
  subject(:service) { described_class.new('last_30_days', custom_from: 30.days.ago.beginning_of_day, custom_to: Time.current) }

  before do
    stub_const('AssetEmbedding', Class.new do
      def self.select(*); end
      def self.count; end
    end)
    allow(Rails.logger).to receive(:error)
  end

  describe '#call' do
    it 'returns cached analytics sections' do
      cache_store = ActiveSupport::Cache::MemoryStore.new
      allow(Rails).to receive(:cache).and_return(cache_store)
      allow(service).to receive(:stats).and_return(total_assets: 10)
      allow(service).to receive(:time_series).and_return(combined: [])
      allow(service).to receive(:breakdowns).and_return(by_status: [])
      allow(service).to receive(:ai_insights).and_return(anomalies: [])

      first = service.call
      second = service.call

      expect(first).to eq(second)
      expect(first).to include(:stats, :time_series, :breakdowns, :ai_insights)
      expect(service).to have_received(:stats).once
    end
  end

  # ===========================================================================
  # Folder filter — new "search box + overlay" feature on the Reports page
  # lets users scope every KPI/chart to one or more selected folders (and
  # their sub-folders). These exercise the real DB end-to-end (no mocks) since
  # the filter touches every private method via raw SQL and AR joins.
  # ===========================================================================
  describe 'folder_ids filter', :aggregate_failures do
    before { stub_const('AssetEmbedding', REAL_ASSET_EMBEDDING_CLASS) }

    let(:owner) { create(:user) }
    let!(:folder_a) { create(:folder, user: owner, name: 'Folder A') }
    let!(:folder_b) { create(:folder, user: owner, name: 'Folder B') }
    let!(:asset_in_a) { create(:asset, user: owner, folder: folder_a, status: :ready, properties: { "content_type" => "image/jpeg", "size" => "1000" }) }
    let!(:asset_in_b) { create(:asset, user: owner, folder: folder_b, status: :ready, properties: { "content_type" => "video/mp4", "size" => "2000" }) }

    it 'scopes stats to only the selected folder' do
      scoped = described_class.new('last_30_days', folder_ids: [ folder_a.id ]).call

      expect(scoped[:stats][:total_assets]).to eq(1)
      expect(scoped[:folder_filter]).to eq(active: true, folder_ids: [ folder_a.id.to_s ])
    end

    it 'includes descendant folders automatically when a parent folder is selected' do
      child = create(:folder, user: owner, parent: folder_a, name: 'Folder A Child')
      create(:asset, user: owner, folder: child, status: :ready, properties: { "content_type" => "image/png", "size" => "500" })

      scoped = described_class.new('last_30_days', folder_ids: [ folder_a.id ]).call

      expect(scoped[:stats][:total_assets]).to eq(2)
    end

    it 'returns all assets when no folder filter is given' do
      unscoped = described_class.new('last_30_days').call

      expect(unscoped[:stats][:total_assets]).to eq(2)
      expect(unscoped[:folder_filter]).to eq(active: false, folder_ids: [])
    end

    it 'scopes the content-type and top-folder breakdowns to the selected folder' do
      scoped = described_class.new('last_30_days', folder_ids: [ folder_a.id ]).call

      expect(scoped[:breakdowns][:by_content_type]).to eq([ { type: 'Image (JPEG)', count: 1 } ])
      expect(scoped[:breakdowns][:top_folders]).to eq([ { name: 'Folder A', count: 1 } ])
    end

    it 'scopes the asset time series to the selected folder' do
      scoped = described_class.new('last_30_days', folder_ids: [ folder_a.id ]).call
      today = Date.current.to_s

      expect(scoped[:time_series][:assets]).to eq([ { date: today, count: 1 } ])
    end

    it 'produces distinct cache entries for different folder filters' do
      cache_store = ActiveSupport::Cache::MemoryStore.new
      allow(Rails).to receive(:cache).and_return(cache_store)

      unscoped = described_class.new('last_30_days').call
      scoped   = described_class.new('last_30_days', folder_ids: [ folder_a.id ]).call

      expect(unscoped[:stats][:total_assets]).not_to eq(scoped[:stats][:total_assets])
    end
  end

  describe '#stats' do
    it 'aggregates dashboard statistics from the supporting models' do
      asset_counts = instance_double('AssetCounts', attributes: {
        'total_assets' => '10',
        'active_assets' => '8',
        'pending_assets' => '1',
        'new_in_range' => '2',
        'in_trash' => '1',
      })
      workflow_counts = instance_double('WorkflowCounts', attributes: {
        'id' => 1,
        'active_workflows' => '3',
        'pending_approvals' => '2',
        'approved_in_range' => '4',
        'rejected_in_range' => '1',
        'avg_approval_hours' => '5.5',
      })
      embedding_counts = instance_double('EmbeddingCounts', attributes: { 'with_embedding' => '6' })

      asset_unscoped = instance_double('AssetUnscoped')
      asset_selected = instance_double('AssetSelected')
      asset_limited = instance_double('AssetLimited', to_a: [ asset_counts ])
      allow(Asset).to receive(:unscoped).and_return(asset_unscoped)
      allow(asset_unscoped).to receive(:select).and_return(asset_selected)
      allow(asset_selected).to receive(:where).with('1=1').and_return(asset_selected)
      allow(asset_selected).to receive(:limit).with(1).and_return(asset_limited)

      workflow_selected = instance_double('WorkflowSelected')
      workflow_limited = instance_double('WorkflowLimited', to_a: [ workflow_counts ])
      allow(WorkflowInstance).to receive(:select).and_return(workflow_selected)
      allow(workflow_selected).to receive(:where).with('1=1').and_return(workflow_selected)
      allow(workflow_selected).to receive(:limit).with(1).and_return(workflow_limited)

      embedding_relation = instance_double('EmbeddingRelation')
      allow(AssetEmbedding).to receive(:select).and_return(embedding_relation)
      allow(embedding_relation).to receive(:limit).with(1).and_return(instance_double('EmbeddingLimit', to_a: [ embedding_counts ]))
      allow(IngestionBatch).to receive(:sum).with(:duplicate_count).and_return(7)
      allow(ActiveRecord::Base.connection).to receive(:select_value).and_return(1.25)

      result = service.send(:stats)

      expect(result).to include(
        total_assets: 10,
        active_workflows: 3,
        storage_used_gb: 1.25,
        duplicates_blocked: 7,
        ai_assets_covered: 6,
        ai_embedding_coverage_pct: 60.0,
        range_label: 'Last 30 Days'
      )
    end

    it 'falls back to zeroed workflow and embedding values when aggregate rows are missing' do
      asset_counts = instance_double('AssetCounts', attributes: {
        'total_assets' => '0',
        'active_assets' => '0',
        'pending_assets' => '0',
        'new_in_range' => '0',
        'in_trash' => '0',
      })

      asset_unscoped = instance_double('AssetUnscoped')
      asset_selected = instance_double('AssetSelected')
      asset_limited = instance_double('AssetLimited', to_a: [ asset_counts ])
      allow(Asset).to receive(:unscoped).and_return(asset_unscoped)
      allow(asset_unscoped).to receive(:select).and_return(asset_selected)
      allow(asset_selected).to receive(:where).with('1=1').and_return(asset_selected)
      allow(asset_selected).to receive(:limit).with(1).and_return(asset_limited)

      workflow_selected = instance_double('WorkflowSelected')
      workflow_limited = instance_double('WorkflowLimited', to_a: [])
      allow(WorkflowInstance).to receive(:select).and_return(workflow_selected)
      allow(workflow_selected).to receive(:where).with('1=1').and_return(workflow_selected)
      allow(workflow_selected).to receive(:limit).with(1).and_return(workflow_limited)

      embedding_relation = instance_double('EmbeddingRelation')
      embedding_limited = instance_double('EmbeddingLimit', to_a: [])
      allow(AssetEmbedding).to receive(:select).and_return(embedding_relation)
      allow(embedding_relation).to receive(:limit).with(1).and_return(embedding_limited)
      allow(IngestionBatch).to receive(:sum).with(:duplicate_count).and_return(0)
      allow(ActiveRecord::Base.connection).to receive(:select_value).and_return(0)

      result = service.send(:stats)

      expect(result).to include(
        total_assets: 0,
        active_workflows: 0,
        pending_approvals: 0,
        approved_in_range: 0,
        rejected_in_range: 0,
        avg_approval_hours: 0.0,
        ai_assets_covered: 0,
        ai_embedding_coverage_pct: 0
      )
    end

    it 'returns an empty hash when aggregation fails' do
      allow(Asset).to receive(:unscoped).and_raise(StandardError, 'boom')

      expect(service.send(:stats)).to eq({})
      expect(Rails.logger).to have_received(:error).with(/stats failed: boom/)
    end

    # Regression test: `:from` was previously a raw named-bind placeholder
    # embedded in a `.select(...)` SQL fragment with a no-op `.where("1=1")`
    # that never actually bound it — Postgres raised `PG::SyntaxError` on
    # every single request, silently swallowed by the rescue, and the whole
    # Reports page KPI/stats section rendered blank. This exercises the real
    # DB (no mocks) to guard against that regression.
    it 'aggregates real statistics without raising a SQL syntax error (regression)', :aggregate_failures do
      create(:asset, user: create(:user), status: :ready, properties: { "content_type" => "image/jpeg", "size" => "500" })
      embedding_relation = instance_double('EmbeddingRelation')
      allow(AssetEmbedding).to receive(:select).and_return(embedding_relation)
      allow(embedding_relation).to receive(:limit).with(1).and_return(
        instance_double('EmbeddingLimit', to_a: [ instance_double('EmbeddingCounts', attributes: { 'with_embedding' => '0' }) ])
      )

      result = nil
      expect(Rails.logger).not_to receive(:error)
      expect { result = service.send(:stats) }.not_to raise_error

      expect(result).not_to eq({})
      expect(result[:total_assets]).to be_a(Integer)
      expect(result[:new_in_range]).to be_a(Integer)
      expect(result[:storage_used_gb]).to be_a(Numeric)
    end
  end

  describe '#time_series' do
    it 'returns raw and merged daily series' do
      sample_date = 10.days.ago.to_date.to_s
      allow(ActiveRecord::Base.connection).to receive(:select_all).and_return(
        [ { 'date' => sample_date, 'count' => '2' } ],
        [ { 'date' => sample_date, 'count' => '1' } ]
      )

      result = service.send(:time_series)

      expect(result[:assets]).to eq([ { date: sample_date, count: 2 } ])
      expect(result[:workflows]).to eq([ { date: sample_date, count: 1 } ])
      combined_entry = result[:combined].find { |r| r[:date] == sample_date }
      expect(combined_entry).to include(date: sample_date, assets: 2, workflows: 1)
    end

    it 'returns empty series on failure' do
      allow(ActiveRecord::Base.connection).to receive(:select_all).and_raise(StandardError, 'boom')

      expect(service.send(:time_series)).to eq(combined: [], assets: [], workflows: [])
    end
  end

  describe '#breakdowns' do
    it 'returns the configured breakdown sections' do
      allow(ActiveRecord::Base.connection).to receive(:select_all).and_return(
        [ { 'type' => 'image/jpeg', 'count' => '2' } ],
        [ { 'email' => 'jane@example.com', 'count' => '3' } ]
      )
      allow(Asset).to receive_message_chain(:unscoped, :where, :group, :count).and_return({ 'ready' => 2 })
      allow(Folder).to receive_message_chain(:active, :left_joins, :where, :group, :order, :limit, :pluck).and_return([ [ 'Marketing', 4 ] ])
      allow(WorkflowInstance).to receive(:count).and_return(8)
      allow(WorkflowInstance).to receive(:where).with(status: %w[pending in_progress]).and_return(instance_double(ActiveRecord::Relation, count: 5))
      allow(WorkflowInstance).to receive(:where).with(status: 'approved').and_return(instance_double(ActiveRecord::Relation, count: 2))
      allow(WorkflowInstance).to receive(:where).with(status: 'rejected').and_return(instance_double(ActiveRecord::Relation, count: 1))

      result = service.send(:breakdowns)

      expect(result).to include(
        by_content_type: [ { type: 'Image (JPEG)', count: 2 } ],
        by_status: [ { status: 'Ready', count: 2 } ],
        top_folders: [ { name: 'Marketing', count: 4 } ]
      )
      expect(result[:workflow_funnel]).to include(stage: 'Triggered', count: 8)
      expect(result[:by_user]).to eq([ { user: 'jane', count: 3 } ])
    end

    it 'preserves nil usernames when contributor emails are missing' do
      allow(ActiveRecord::Base.connection).to receive(:select_all).and_return(
        [ { 'type' => 'image/jpeg', 'count' => '2' } ],
        [ { 'email' => nil, 'count' => '3' } ]
      )
      allow(Asset).to receive_message_chain(:unscoped, :where, :group, :count).and_return({ 'ready' => 2 })
      allow(Folder).to receive_message_chain(:active, :left_joins, :where, :group, :order, :limit, :pluck).and_return([ [ 'Marketing', 4 ] ])
      allow(WorkflowInstance).to receive(:count).and_return(8)
      allow(WorkflowInstance).to receive(:where).with(status: %w[pending in_progress]).and_return(instance_double(ActiveRecord::Relation, count: 5))
      allow(WorkflowInstance).to receive(:where).with(status: 'approved').and_return(instance_double(ActiveRecord::Relation, count: 2))
      allow(WorkflowInstance).to receive(:where).with(status: 'rejected').and_return(instance_double(ActiveRecord::Relation, count: 1))

      result = service.send(:breakdowns)

      expect(result[:by_user]).to eq([ { user: nil, count: 3 } ])
    end

    it 'returns an empty hash when breakdown generation fails' do
      allow(ActiveRecord::Base.connection).to receive(:select_all).and_raise(StandardError, 'boom')

      expect(service.send(:breakdowns)).to eq({})
    end

    # Regression test: content-type bucketing previously grouped/limited by
    # the *raw* mime type in SQL before simplifying to a friendly label,
    # so e.g. "application/msword" and "...wordprocessingml.document" showed
    # up as two separate "Word Document" pie/bar entries instead of merging.
    it 'merges distinct raw content types into a single bucket entry (regression)' do
      user = create(:user)
      create(:asset, user: user, status: :ready, properties: { "content_type" => "application/msword" })
      create(:asset, user: user, status: :ready,
                     properties: { "content_type" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document" })
      allow(Asset).to receive_message_chain(:unscoped, :where, :group, :count).and_return({})
      allow(Folder).to receive_message_chain(:active, :left_joins, :where, :group, :order, :limit, :pluck).and_return([])
      allow(WorkflowInstance).to receive(:count).and_return(0)
      allow(WorkflowInstance).to receive(:where).and_return(instance_double(ActiveRecord::Relation, count: 0))
      allow(ActiveRecord::Base.connection).to receive(:select_all).and_call_original

      result = service.send(:breakdowns)
      word_rows = result[:by_content_type].select { |row| row[:type] == 'Word Document' }

      expect(word_rows.length).to eq(1)
      expect(word_rows.first[:count]).to eq(2)
    end
  end

  describe '#ai_insights' do
    it 'builds threshold-based anomaly and opportunity messages' do
      allow(ActiveRecord::Base.connection).to receive(:select_all).and_return(
        [
          { 'date' => '2026-06-01', 'cnt' => '10' },
          { 'date' => '2026-06-02', 'cnt' => '10' },
          { 'date' => '2026-06-03', 'cnt' => '10' },
          { 'date' => '2026-06-04', 'cnt' => '10' },
          { 'date' => '2026-06-05', 'cnt' => '10' },
          { 'date' => '2026-06-06', 'cnt' => '10' },
          { 'date' => '2026-06-07', 'cnt' => '40' },
        ]
      )

      asset_active_scope = instance_double(ActiveRecord::Relation)
      allow(Asset).to receive(:active).and_return(asset_active_scope)
      allow(asset_active_scope).to receive(:where).with("properties->>'alt_text' IS NULL OR properties->>'alt_text' = ''").and_return(instance_double(ActiveRecord::Relation, count: 30))
      allow(asset_active_scope).to receive(:count).and_return(100)
      allow(asset_active_scope).to receive(:where).with("(properties->>'license_expires_at')::timestamp < ?", anything).and_return(instance_double(ActiveRecord::Relation, count: 5))
      allow(AssetEmbedding).to receive(:count).and_return(20)
      allow(Asset).to receive(:trashed).and_return(instance_double(ActiveRecord::Relation, count: 150))
      allow(WorkflowInstance).to receive(:where).with(status: 'pending').and_return(instance_double(ActiveRecord::Relation, where: instance_double(ActiveRecord::Relation, count: 3)))
      allow(IngestionBatch).to receive(:sum).with(:duplicate_count).and_return(300)

      result = service.send(:ai_insights)

      expect(result[:anomalies].join(' ')).to include('Upload spike detected', 'licenses expiring', 'workflow reviews')
      expect(result[:suggestions].join(' ')).to include('missing alt_text', 'lack vector embeddings', 'in the bin')
      expect(result[:opportunities].join(' ')).to include('duplicate storage has been blocked')
    end

    it 'skips the upload-spike anomaly when there are fewer than seven days of data' do
      allow(ActiveRecord::Base.connection).to receive(:select_all).and_return(
        [
          { 'date' => '2026-06-01', 'cnt' => '4' },
          { 'date' => '2026-06-02', 'cnt' => '4' },
          { 'date' => '2026-06-03', 'cnt' => '4' },
        ]
      )

      asset_active_scope = instance_double(ActiveRecord::Relation)
      allow(Asset).to receive(:active).and_return(asset_active_scope)
      allow(asset_active_scope).to receive(:where).with("properties->>'alt_text' IS NULL OR properties->>'alt_text' = ''").and_return(instance_double(ActiveRecord::Relation, count: 1))
      allow(asset_active_scope).to receive(:where).with("(properties->>'license_expires_at')::timestamp < ?", anything).and_return(instance_double(ActiveRecord::Relation, count: 0))
      allow(asset_active_scope).to receive(:count).and_return(10)
      allow(AssetEmbedding).to receive(:count).and_return(9)
      allow(Asset).to receive(:trashed).and_return(instance_double(ActiveRecord::Relation, count: 50))
      allow(WorkflowInstance).to receive(:where).with(status: 'pending').and_return(instance_double(ActiveRecord::Relation, where: instance_double(ActiveRecord::Relation, count: 0)))
      allow(IngestionBatch).to receive(:sum).with(:duplicate_count).and_return(100)

      result = service.send(:ai_insights)

      expect(result[:anomalies]).to eq([])
      expect(result[:suggestions]).to eq([])
      expect(result[:opportunities]).to eq([])
    end

    it 'skips threshold-based messages when counts stay below alert levels' do
      allow(ActiveRecord::Base.connection).to receive(:select_all).and_return(
        Array.new(7) { |i| { 'date' => "2026-06-0#{i + 1}", 'cnt' => '10' } }
      )

      asset_active_scope = instance_double(ActiveRecord::Relation)
      allow(Asset).to receive(:active).and_return(asset_active_scope)
      allow(asset_active_scope).to receive(:where).with("properties->>'alt_text' IS NULL OR properties->>'alt_text' = ''").and_return(instance_double(ActiveRecord::Relation, count: 2))
      allow(asset_active_scope).to receive(:where).with("(properties->>'license_expires_at')::timestamp < ?", anything).and_return(instance_double(ActiveRecord::Relation, count: 0))
      allow(asset_active_scope).to receive(:count).and_return(20)
      allow(AssetEmbedding).to receive(:count).and_return(19)
      allow(Asset).to receive(:trashed).and_return(instance_double(ActiveRecord::Relation, count: 10))
      allow(WorkflowInstance).to receive(:where).with(status: 'pending').and_return(instance_double(ActiveRecord::Relation, where: instance_double(ActiveRecord::Relation, count: 0)))
      allow(IngestionBatch).to receive(:sum).with(:duplicate_count).and_return(50)

      result = service.send(:ai_insights)

      expect(result[:anomalies]).to eq([])
      expect(result[:suggestions]).to eq([])
      expect(result[:opportunities]).to eq([])
    end

    it 'returns empty arrays when insight generation fails' do
      allow(ActiveRecord::Base.connection).to receive(:select_all).and_raise(StandardError, 'boom')

      expect(service.send(:ai_insights)).to include(anomalies: [], suggestions: [], opportunities: [])
    end
  end

  describe 'helper methods' do
    it 'computes the date range for supported presets and falls back for unknown keys' do
      travel_to(Time.zone.parse('2026-07-03 09:27:45')) do
        expect(service.send(:compute_date_from, 'last_7_days')).to eq(7.days.ago.beginning_of_day)
        expect(service.send(:compute_date_from, 'last_30_days')).to eq(30.days.ago.beginning_of_day)
        expect(service.send(:compute_date_from, 'last_90_days')).to eq(90.days.ago.beginning_of_day)
        expect(service.send(:compute_date_from, 'this_year')).to eq(Time.current.beginning_of_year)
        expect(service.send(:compute_date_from, 'this_quarter')).to eq(Time.current.beginning_of_quarter)
        expect(service.send(:compute_date_from, 'unexpected')).to eq(30.days.ago.beginning_of_day)
      end
    end

    it 'returns user-facing range labels' do
      expect(service.send(:range_label)).to eq('Last 30 Days')
    end

    it 'simplifies known mime types' do
      expect(service.send(:simplify_mime, 'image/jpeg')).to eq('Image (JPEG)')
      expect(service.send(:simplify_mime, 'video/mp4')).to eq('Video (MP4)')
      expect(service.send(:simplify_mime, 'application/pdf')).to eq('PDF Document')
      expect(service.send(:simplify_mime, 'application/zip')).to eq('ZIP Archive')
      expect(service.send(:simplify_mime, 'application/vnd.ms-excel')).to eq('Spreadsheet')
      expect(service.send(:simplify_mime, 'application/wordprocessingml.document')).to eq('Word Document')
      expect(service.send(:simplify_mime, 'text/plain')).to eq('text/plain')
      expect(service.send(:simplify_mime, nil)).to eq('Unknown')
    end

    it 'merges sparse time series over the provided date range' do
      result = service.send(:merge_time_series, { assets: [ { date: '2026-06-01', count: 2 } ], workflows: [] }, Date.new(2026, 6, 1), Date.new(2026, 6, 2))

      expect(result).to eq([
        { date: '2026-06-01', assets: 2, workflows: 0 },
        { date: '2026-06-02', assets: 0, workflows: 0 },
      ])
    end
  end
end
