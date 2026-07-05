# frozen_string_literal: true

# REST API for managing individual workflow instances.
#
# == Endpoint summary
#
# | Method | Path                                          | Action        | Auth        |
# |--------|-----------------------------------------------|---------------|-------------|
# | GET    | /api/v1/workflow_instances                    | index         | admin       |
# | GET    | /api/v1/workflow_instances/:id                | show          | admin       |
# | POST   | /api/v1/workflow_instances/:id/force_cancel   | force_cancel  | admin       |
# | DELETE | /api/v1/workflow_instances/:id                | destroy       | admin       |
# | POST   | /api/v1/workflows/bulk_stop                   | bulk_stop     | admin       |
# | POST   | /api/v1/workflows/bulk_reassign               | bulk_reassign | admin       |
# | POST   | /api/v1/workflows/bulk_trigger                | bulk_trigger  | user        |
class Api::V1::WorkflowInstancesController < ApplicationController
  before_action :authenticate_hybrid!
  before_action :require_admin!, except: %i[bulk_trigger]
  before_action :set_instance, only: %i[show force_cancel destroy]

  PAGE_SIZE = 50

  # GET /api/v1/workflow_instances
  def index
    scope = WorkflowInstance.includes(:workflow, :asset, :current_step, :cancelled_by)
                            .order(created_at: :desc)
                            .limit(PAGE_SIZE)

    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.where(workflow_id: params[:workflow_id]) if params[:workflow_id].present?

    render json: {
      total:     WorkflowInstance.count,
      instances: scope.map { |i| serialize_instance(i) },
    }
  end

  # GET /api/v1/workflow_instances/:id
  def show
    render json: serialize_instance(@instance, detail: true)
  end

  # POST /api/v1/workflow_instances/:id/force_cancel
  def force_cancel
    if @instance.terminal?
      return render json: { error: "Instance is already #{@instance.status}." },
                    status: :unprocessable_entity
    end

    reason = params[:reason].presence || "Admin force-cancel via Operations Center"
    @instance.force_cancel!(current_user, reason)

    render json: { message: "Instance #{@instance.id} cancelled.", instance: serialize_instance(@instance) }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # DELETE /api/v1/workflow_instances/:id
  # Admin can hard-delete a terminal (completed/rejected/canceled) instance.
  def destroy
    unless @instance.terminal?
      return render json: { error: "Cannot delete a running instance. Force-cancel it first." },
                    status: :unprocessable_entity
    end

    @instance.destroy!
    render json: { message: "Instance #{params[:id]} deleted." }
  end

  # POST /api/v1/workflows/bulk_stop
  def bulk_stop
    ids       = Array(params[:ids])
    instances = WorkflowInstance.where(id: ids).where.not(status: WorkflowInstance::TERMINAL_STATUSES)
    reason    = params[:reason].presence || "Admin bulk-stop via Operations Center"

    ActiveRecord::Base.transaction do
      instances.each { |inst| inst.force_cancel!(current_user, reason) }
    end

    render json: { message: "#{instances.count} instance(s) stopped.", stopped_ids: instances.map(&:id) }
  end

  # POST /api/v1/workflows/bulk_reassign
  def bulk_reassign
    ids           = Array(params[:ids])
    new_user_id   = params[:user_id]
    new_group_id  = params[:group_id]

    unless new_user_id.present? || new_group_id.present?
      return render json: { error: "Provide user_id or group_id for reassignment." },
                    status: :unprocessable_entity
    end

    instances = WorkflowInstance.where(id: ids, status: "in_progress")
    count     = 0

    ActiveRecord::Base.transaction do
      instances.each do |inst|
        # Re-assign all pending tasks for this instance
        pending_tasks = inst.workflow_tasks.where(status: "pending")

        if new_user_id.present?
          new_user = User.find_by(id: new_user_id)
          next unless new_user

          pending_tasks.update_all(user_id: new_user_id)
          count += 1
          TaskNotificationWorker.perform_async(pending_tasks.first.id) if pending_tasks.any?
        end

        if new_group_id.present?
          group = UserGroup.find_by(id: new_group_id)
          next unless group

          # Replace tasks with one per group member
          pending_tasks.destroy_all
          group.users.each do |user|
            task = WorkflowTask.create!(
              workflow_instance: inst,
              workflow_step:     inst.current_step,
              user:              user,
              status:            "pending",
            )
            TaskNotificationWorker.perform_async(task.id)
          end
          count += 1
        end
      end
    end

    render json: { message: "#{count} instance(s) reassigned." }
  end

  # POST /api/v1/workflows/bulk_trigger
  #
  # Manual entry point for the AssetGrid "Workflow" toolbar action: lets any
  # authenticated user kick off an *active* Workflow blueprint for a batch of
  # selected assets and/or folders (folders are expanded to every active asset
  # they contain, recursively). Reuses the same {WorkflowInitiatorWorker} that
  # {WorkflowEvaluatorService} enqueues for automatic, event-driven triggers.
  def bulk_trigger
    workflow = Workflow.find_by(id: params[:workflow_id], status: "active")
    return render json: { error: "Workflow not found or inactive." }, status: :unprocessable_entity unless workflow

    asset_ids  = Array(params[:asset_ids])
    folder_ids = Array(params[:folder_ids])

    if asset_ids.empty? && folder_ids.empty?
      return render json: { error: "Select at least one asset or folder." }, status: :unprocessable_entity
    end

    resolved_ids = (asset_ids + folder_ids.flat_map { |folder_id| asset_ids_in_folder(folder_id) }).uniq
    assets       = Asset.active.where(id: resolved_ids)

    assets.find_each { |asset| WorkflowInitiatorWorker.perform_async(asset.id, workflow.id) }

    render json: {
      message:     "Workflow '#{workflow.name}' queued for #{assets.count} asset(s).",
      queued:      assets.count,
      workflow_id: workflow.id,
    }, status: :accepted
  end

  private

  # Recursively collects the ids of every active asset inside +folder_id+ and
  # any of its descendant folders.
  def asset_ids_in_folder(folder_id)
    folder = Folder.find_by(id: folder_id)
    return [] unless folder

    folder_ids = [ folder.id ]
    queue      = [ folder ]

    until queue.empty?
      current = queue.shift
      current.children.each do |child|
        folder_ids << child.id
        queue << child
      end
    end

    Asset.active.where(folder_id: folder_ids).pluck(:id)
  end

  def set_instance
    @instance = WorkflowInstance.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Workflow instance not found." }, status: :not_found
  end

  def serialize_instance(inst, detail: false)
    base = {
      id:              inst.id,
      workflow_id:     inst.workflow_id,
      workflow_name:   inst.workflow&.name,
      asset_id:        inst.asset_id,
      asset_name:      inst.asset&.title,
      status:          inst.status,
      current_step:    inst.current_step&.title,
      started_at:      inst.started_at,
      completed_at:    inst.completed_at,
      cancel_reason:   inst.cancel_reason,
      cancelled_by:    inst.cancelled_by&.email,
      terminal:        inst.terminal?,
      created_at:      inst.created_at,
    }

    if detail
      tasks = inst.workflow_tasks.includes(:user, :workflow_step).order(created_at: :asc).map do |t|
        {
          id:           t.id,
          step_name:    t.workflow_step.title,
          user_email:   t.user.email,
          status:       t.status,
          comment:      t.comment,
          completed_at: t.completed_at,
        }
      end
      base[:tasks]     = tasks
      base[:audit_log] = inst.audit_log || []
    end

    base
  end
end
