# frozen_string_literal: true

# An AiBatchJob is a single on-demand, admin-configured AI batch run launched
# from the "AI Batch Tasks" screen (/ai/tasks, legacy /ai/batch).
#
# The available +task_type+ and +target_scope+ values are defined declaratively
# in {Ai::BatchTaskRegistry}, so new AI capabilities can be added without
# touching this model.
#
# == Lifecycle
#
#   queued → running → completed | failed | cancelled
#                  ↘ paused ↗
#
# On create the {AiBatchJobWorker} resolves the target dataset, marks the job
# +running+, and broadcasts an `ai_batch.dispatch` event to the AI Gateway over
# Redis.  The gateway streams progress back via
# POST /api/v1/ai_batch_jobs/:id/progress.
#
# @see Ai::BatchTaskRegistry
# @see AiBatchJobWorker
class AiBatchJob < ApplicationRecord
  STATUSES         = %w[queued running paused completed failed cancelled].freeze
  TERMINAL_STATUSES = %w[completed failed cancelled].freeze
  MAX_CONCURRENCY  = 500
  MIN_CONCURRENCY  = 1

  # ---------------------------------------------------------------------------
  # Associations
  # ---------------------------------------------------------------------------

  belongs_to :created_by, class_name: "User", foreign_key: :created_by_id, optional: true

  # ---------------------------------------------------------------------------
  # Validations
  # ---------------------------------------------------------------------------

  validates :task_type,    presence: true, inclusion: { in: ->(_) { Ai::BatchTaskRegistry.task_keys } }
  validates :target_scope, presence: true, inclusion: { in: ->(_) { Ai::BatchTaskRegistry.scope_keys } }
  validates :status,       presence: true, inclusion: { in: STATUSES }
  validates :concurrency,  numericality: { only_integer: true, greater_than_or_equal_to: MIN_CONCURRENCY, less_than_or_equal_to: MAX_CONCURRENCY }
  validates :total_count, :processed_count, :succeeded_count, :failed_count,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # ---------------------------------------------------------------------------
  # Scopes
  # ---------------------------------------------------------------------------

  scope :recent,   -> { order(created_at: :desc) }
  scope :active,   -> { where(status: %w[queued running paused]) }
  scope :terminal, -> { where(status: TERMINAL_STATUSES) }

  # ---------------------------------------------------------------------------
  # Instance methods
  # ---------------------------------------------------------------------------

  # Progress as a 0–100 percentage. Returns 0 when nothing is queued yet.
  #
  # @return [Integer]
  def progress_percent
    return 0 if total_count.to_i.zero?

    ((processed_count.to_f / total_count) * 100).round.clamp(0, 100)
  end

  # @return [Boolean] true when the job has reached a terminal state.
  def terminal?
    TERMINAL_STATUSES.include?(status)
  end

  # Resolved registry task descriptor (may be nil if removed from the registry).
  #
  # @return [Ai::BatchTaskRegistry::Task, nil]
  def task_descriptor
    Ai::BatchTaskRegistry.task(task_type)
  end

  # The payload broadcast to the AI Gateway to start processing.
  #
  # @param target_ids [Array<String>]
  # @return [Hash]
  def to_gateway_payload(target_ids)
    {
      event:      "ai_batch.dispatch",
      job_id:     id,
      task_type:  task_type,
      capability: task_descriptor&.gateway_capability,
      tools:      task_descriptor&.default_tools || [],
      target_scope: target_scope,
      concurrency:  concurrency,
      options:      options,
      target_ids:   target_ids,
    }
  end
end
