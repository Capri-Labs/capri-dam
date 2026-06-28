# frozen_string_literal: true

# REST API for AI Agent Workflows (admin-only write; any authenticated user can read).
#
# These workflows are autonomous LangChain agent pipelines that fire on DAM
# system events or on schedule.  On create/update/toggle, the workflow config
# is broadcast to the AI Gateway over Redis so the gateway can subscribe/
# unsubscribe from the relevant event stream in real time.
#
# == Endpoint summary
#
# | Method | Path | Action | Auth |
# |--------|------|--------|------|
# | GET    | /api/v1/agent_workflows            | index   | any user  |
# | POST   | /api/v1/agent_workflows            | create  | admin     |
# | GET    | /api/v1/agent_workflows/:id        | show    | any user  |
# | PATCH  | /api/v1/agent_workflows/:id        | update  | admin     |
# | DELETE | /api/v1/agent_workflows/:id        | destroy | admin     |
# | PATCH  | /api/v1/agent_workflows/:id/toggle | toggle  | admin     |
# | POST   | /api/v1/agent_workflows/:id/trigger| trigger | admin     |
# | GET    | /api/v1/agent_workflows/:id/executions | executions | any user |
# | POST   | /api/v1/agent_workflows/:id/executions | log_execution | gateway secret |
class Api::V1::AgentWorkflowsController < ApplicationController
  # log_execution is a machine-to-machine endpoint authenticated solely by the
  # shared gateway secret — it must NOT require a Devise/OAuth session.
  before_action :authenticate_hybrid!, except: %i[log_execution]
  before_action :require_admin!, except: %i[index show executions log_execution]
  before_action :authenticate_gateway_secret!, only: %i[log_execution]
  before_action :set_workflow, except: %i[index create]

  EXECUTION_PAGE_SIZE = 20

  # GET /api/v1/agent_workflows
  def index
    workflows = AgentWorkflow.includes(:created_by)
                             .order(updated_at: :desc)
    render json: workflows.map { |wf| serialize(wf) }
  end

  # POST /api/v1/agent_workflows
  def create
    wf = AgentWorkflow.new(workflow_params)
    wf.created_by = current_user
    if wf.save
      render json: serialize(wf), status: :created
    else
      render json: { errors: wf.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # GET /api/v1/agent_workflows/:id
  def show
    render json: serialize(@workflow)
  end

  # PATCH /api/v1/agent_workflows/:id
  def update
    if @workflow.update(workflow_params)
      render json: serialize(@workflow)
    else
      render json: { errors: @workflow.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/agent_workflows/:id
  def destroy
    @workflow.destroy
    head :no_content
  end

  # PATCH /api/v1/agent_workflows/:id/toggle
  # Flips the `active` flag and broadcasts to the AI Gateway.
  def toggle
    @workflow.update!(active: !@workflow.active)
    render json: { id: @workflow.id, active: @workflow.active }
  end

  # POST /api/v1/agent_workflows/:id/trigger
  # Manually fires the workflow on demand via the AI Gateway.
  def trigger
    payload = {
      event:       "agent_workflow.manual_trigger",
      workflow_id: @workflow.id,
      triggered_by: current_user.id,
    }
    Sidekiq.redis { |conn| conn.publish("ai_gateway_events", payload.to_json) }
    render json: { message: "Workflow trigger signal sent.", workflow_id: @workflow.id }
  rescue StandardError => e
    render json: { error: "Failed to trigger workflow: #{e.message}" },
           status: :service_unavailable
  end

  # GET /api/v1/agent_workflows/:id/executions
  # Returns paginated execution history for a single workflow.
  def executions
    page  = (params[:page].presence || 1).to_i
    execs = @workflow.agent_executions
                     .recent
                     .limit(EXECUTION_PAGE_SIZE)
                     .offset((page - 1) * EXECUTION_PAGE_SIZE)
    total = @workflow.agent_executions.count

    render json: {
      total:      total,
      page:       page,
      per_page:   EXECUTION_PAGE_SIZE,
      executions: execs.map { |e| serialize_execution(e) },
    }
  end

  # POST /api/v1/agent_workflows/:id/executions
  # Internal: called by the AI Gateway to record an execution result.
  # Authentication is via X-Gateway-Secret header, not Devise/OAuth.
  def log_execution
    attrs = execution_params.to_h
    attrs[:started_at]   ||= Time.current
    attrs[:completed_at] ||= Time.current unless attrs[:status] == "running"

    exec = @workflow.agent_executions.create!(attrs)
    render json: serialize_execution(exec), status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  private

  def set_workflow
    @workflow = AgentWorkflow.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Agent workflow not found." }, status: :not_found
  end

  def workflow_params
    params.require(:agent_workflow).permit(
      :name, :description, :trigger_event,
      :agent_model, :active,
      tools_enabled: [],
      metadata: {},
    )
  end

  def execution_params
    params.require(:agent_execution).permit(
      :trigger_type, :status, :summary,
      :error_message, :duration_ms, :started_at, :completed_at,
      trigger_payload: {},
      output: {},
    )
  end

  def serialize(wf)
    {
      id:           wf.id,
      name:         wf.name,
      description:  wf.description,
      trigger_event: wf.trigger_event,
      agent_model:  wf.agent_model,
      tools_enabled: wf.tools_enabled,
      active:       wf.active,
      metadata:     wf.metadata,
      created_by:   wf.created_by&.email,
      created_at:   wf.created_at,
      updated_at:   wf.updated_at,
      # Computed stats (may be nil when no executions yet)
      reliability:    wf.reliability,
      avg_duration_ms: wf.avg_duration_ms,
      execution_count: wf.agent_executions.count,
    }
  end

  def serialize_execution(exec)
    {
      id:              exec.id,
      agent_workflow_id: exec.agent_workflow_id,
      trigger_type:    exec.trigger_type,
      trigger_payload: exec.trigger_payload,
      status:          exec.status,
      summary:         exec.summary,
      output:          exec.output,
      error_message:   exec.error_message,
      duration_ms:     exec.duration_ms,
      started_at:      exec.started_at,
      completed_at:    exec.completed_at,
    }
  end

  # Validates the shared secret sent by the AI Gateway.
  # This is not the same as Devise/Doorkeeper auth — it's a lightweight
  # machine-to-machine token so the gateway can write execution records.
  def authenticate_gateway_secret!
    expected = Rails.application.credentials.dig(:ai_gateway, :secret).presence ||
               ENV.fetch("GATEWAY_SECRET", nil)
    received = request.headers["X-Gateway-Secret"]

    return if expected.present? && ActiveSupport::SecurityUtils.secure_compare(expected, received.to_s)

    render json: { error: "Unauthorized" }, status: :unauthorized
  end
end
