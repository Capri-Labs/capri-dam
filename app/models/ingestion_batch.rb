class IngestionBatch < ApplicationRecord
  belongs_to :connector, class_name: 'SystemConnector', optional: true
  has_many   :ingestion_items, dependent: :destroy

  validates :name, :source_type, presence: true

  # ── State Machine ─────────────────────────────────────────────────────────
  # `instance_methods: false` avoids a clash between the `committed` state and
  # ActiveRecord's internal `committed!` transaction callback. We re-add the
  # read-only `?` predicates (the unused `!` bang setters are what collided).
  enum :status, {
    initializing:  0,
    extracting:    1,
    transforming:  2,
    review_needed: 3,
    committed:     4,
    failed:        5
  }, instance_methods: false

  statuses.each_key do |state|
    define_method("#{state}?") { status == state }
  end

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
      report_snapshot_id: report_snapshot_id
    }
  end
end