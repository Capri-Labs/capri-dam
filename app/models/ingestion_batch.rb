class IngestionBatch < ApplicationRecord
  belongs_to :connector, class_name: "SystemConnector", optional: true
  belongs_to :destination_folder, class_name: "Folder", optional: true
  has_many   :ingestion_items, dependent: :destroy

  validates :name, :source_type, presence: true

  # ── State Machine ─────────────────────────────────────────────────────────
  enum :status, {
    initializing:  0,
    extracting:    1,
    transforming:  2,
    review_needed: 3,
    committed:     4,
    failed:        5,
  }, instance_methods: false

  statuses.each_key do |state|
    define_method("#{state}?") { status == state }
  end

  # ── Named Scopes ──────────────────────────────────────────────────────────
  IN_PROGRESS_STATUSES = %w[initializing extracting transforming review_needed].freeze

  scope :in_progress,       -> { where(status: IN_PROGRESS_STATUSES.map { |s| statuses[s] }) }
  scope :committed_batches, -> { where(status: statuses["committed"]) }
  scope :failed_batches,    -> { where(status: statuses["failed"]) }
  scope :search_by_name,    ->(q) { where("name ILIKE ?", "%#{sanitize_sql_like(q)}%") }

  # ── Progress ──────────────────────────────────────────────────────────────
  def calculate_progress!
    update!(
      processed_count: ingestion_items.where.not(status: :pending).count,
      total_count:     ingestion_items.count,
      duplicate_count: ingestion_items.where(status: :flagged_duplicate).count,
      error_count:     ingestion_items.where(status: :flagged_error).count
    )
  end

  def progress_pct
    return 0 if total_count.to_i.zero?
    ((processed_count.to_f / total_count) * 100).round(1)
  end

  def source_label
    DamProviders.label_for(source_type)
  end

  # ── Aggregate Stats (dashboard metrics endpoint) ──────────────────────────
  def self.aggregate_stats
    rel = all
    {
      total_batches:              rel.count,
      active_batches:             rel.in_progress.count,
      completed_batches:          rel.committed_batches.count,
      failed_batches:             rel.failed_batches.count,
      total_assets_staged:        rel.sum(:total_count),
      total_assets_committed:     rel.sum(:committed_count),
      total_duplicates_blocked:   rel.sum(:duplicate_count),
      total_errors:               rel.sum(:error_count),
      estimated_storage_saved_gb: (rel.sum(:duplicate_count) * 5.0 / 1024).round(2),
      estimated_cost_savings_usd: (rel.sum(:duplicate_count) * 5.0 / 1024 * 0.023).round(2),
    }
  end

  # ── Summary Stats ─────────────────────────────────────────────────────────
  def summary
    {
      id:                 id,
      name:               name,
      source_type:        source_type,
      source_label:       source_label,
      status:             status,
      progress_pct:       progress_pct,
      total_count:        total_count,
      processed_count:    processed_count,
      committed_count:    committed_count.to_i,
      duplicate_count:    duplicate_count.to_i,
      error_count:        error_count.to_i,
      started_at:         started_at,
      completed_at:       completed_at,
      created_at:         created_at,
      connector_name:     connector&.name,
      destination_folder_id:   destination_folder_id,
      destination_folder_name: destination_folder&.name,
      report_snapshot_id: report_snapshot_id,
      migrate_metadata:   migrate_metadata,
    }
  end
end
