# frozen_string_literal: true

# REST API for AI Batch Tasks (admin-only management; gateway-secret callback).
#
# Backs the "AI Batch Tasks" screen at /ai/tasks (legacy /ai/batch).  Admins
# launch on-demand AI batch runs; the worker dispatches them to the AI Gateway,
# which streams progress back to the +progress+ endpoint.
#
# == Endpoint summary
#
# | Method | Path | Action | Auth |
# |--------|------|--------|------|
# | GET    | /api/v1/ai_batch_jobs             | index      | admin          |
# | POST   | /api/v1/ai_batch_jobs             | create     | admin          |
# | GET    | /api/v1/ai_batch_jobs/task_types  | task_types | admin          |
# | GET    | /api/v1/ai_batch_jobs/:id         | show       | admin          |
# | POST   | /api/v1/ai_batch_jobs/:id/cancel  | cancel     | admin          |
# | POST   | /api/v1/ai_batch_jobs/:id/progress| progress   | gateway secret |
class Api::V1::AiBatchJobsController < ApplicationController
  # progress is a machine-to-machine endpoint authenticated solely by the
  # shared gateway secret — it must NOT require a Devise/OAuth session.
  before_action :authenticate_hybrid!, except: %i[progress]
  before_action :require_admin!,       except: %i[progress]
  before_action :authenticate_gateway_secret!, only: %i[progress]
  before_action :set_job, only: %i[show cancel progress]

  PAGE_SIZE = 25

  # GET /api/v1/ai_batch_jobs
  def index
    page = (params[:page].presence || 1).to_i.clamp(1, 10_000)
    jobs = AiBatchJob.includes(:created_by)
                     .recent
                     .limit(PAGE_SIZE)
                     .offset((page - 1) * PAGE_SIZE)

    render json: {
      total:    AiBatchJob.count,
      page:     page,
      per_page: PAGE_SIZE,
      jobs:     jobs.map { |j| serialize(j) },
    }
  end

  # GET /api/v1/ai_batch_jobs/task_types
  # Registry metadata that drives the data-driven UI form.
  def task_types
    render json: Ai::BatchTaskRegistry.as_json_meta
  end

  # GET /api/v1/ai_batch_jobs/:id
  def show
    render json: serialize(@job)
  end

  # POST /api/v1/ai_batch_jobs
  def create
    job = AiBatchJob.new(job_params)
    job.created_by = current_user
    job.status     = "queued"

    if job.save
      AiBatchJobWorker.perform_async(job.id)
      render json: serialize(job), status: :created
    else
      render json: { errors: job.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # POST /api/v1/ai_batch_jobs/:id/cancel
  def cancel
    if @job.terminal?
      return render json: { error: "Job already #{@job.status}." }, status: :unprocessable_entity
    end

    @job.update!(status: "cancelled", completed_at: Time.current)
    broadcast_cancellation(@job)
    render json: serialize(@job)
  end

  # POST /api/v1/ai_batch_jobs/:id/progress
  # Internal: called by the AI Gateway to stream live progress counters.
  # Authentication is via X-Gateway-Secret header, not Devise/OAuth.
  def progress
    @job.update!(progress_params)
    render json: serialize(@job)
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  private

  def set_job
    @job = AiBatchJob.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: "AI batch job not found." }, status: :not_found
  end

  def job_params
    params.require(:ai_batch_job).permit(
      :task_type, :target_scope, :concurrency,
      options: {},
    )
  end

  # Only counters / status / error are writable by the gateway — never the
  # task definition.
  def progress_params
    permitted = params.require(:ai_batch_job).permit(
      :status, :total_count, :processed_count,
      :succeeded_count, :failed_count, :error_message,
    ).to_h

    if AiBatchJob::TERMINAL_STATUSES.include?(permitted["status"]) && @job.completed_at.nil?
      permitted["completed_at"] = Time.current
    end
    permitted
  end

  def serialize(job)
    {
      id:              job.id,
      task_type:       job.task_type,
      task_label:      job.task_descriptor&.label,
      target_scope:    job.target_scope,
      status:          job.status,
      concurrency:     job.concurrency,
      options:         job.options,
      total_count:     job.total_count,
      processed_count: job.processed_count,
      succeeded_count: job.succeeded_count,
      failed_count:    job.failed_count,
      progress_percent: job.progress_percent,
      error_message:   job.error_message,
      created_by:      job.created_by&.email,
      started_at:      job.started_at,
      completed_at:    job.completed_at,
      created_at:      job.created_at,
      updated_at:      job.updated_at,
    }
  end

  def broadcast_cancellation(job)
    payload = { event: "ai_batch.cancelled", job_id: job.id }.to_json
    Sidekiq.redis { |conn| conn.publish("ai_gateway_events", payload) }
  rescue StandardError => e
    Rails.logger.warn("[AiBatchJob##{job.id}] cancellation broadcast skipped: #{e.message}")
  end

  # Validates the shared secret sent by the AI Gateway (machine-to-machine).
  def authenticate_gateway_secret!
    expected = Rails.application.credentials.dig(:ai_gateway, :secret).presence ||
               ENV.fetch("GATEWAY_SECRET", nil)
    received = request.headers["X-Gateway-Secret"]

    return if expected.present? && ActiveSupport::SecurityUtils.secure_compare(expected, received.to_s)

    render json: { error: "Unauthorized" }, status: :unauthorized
  end
end
