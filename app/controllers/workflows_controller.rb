class WorkflowsController < ApplicationController
  before_action :authenticate_user!
  # Updated: Only include actions that actually exist in the controller
  before_action :set_workflow, only: [ :update, :destroy, :toggle_status ]

  rescue_from ActiveRecord::RecordNotFound do |e|
    render json: { error: e.message }, status: :not_found
  end

  def index
    @active_view = "Workflows"
    page     = [ params[:page].to_i, 1 ].max
    per_page = 25

    respond_to do |format|
      # ---------------------------------------------------------
      # 1. THE API RESPONSE (For React fetch requests)
      # ---------------------------------------------------------
      format.json do
        scope = Workflow.all.order(created_at: :desc)

        # Backward compatible: when no `page` param is given, return the
        # legacy bare array (consumed by TriggerWorkflowDialog.jsx's workflow
        # picker, which needs the full list of active workflows to choose from).
        if params[:page].present?
          total = scope.count
          @workflows = scope.limit(per_page).offset((page - 1) * per_page)
          render json: {
            workflows: @workflows.as_json(include: :workflow_steps),
            pagination: {
              page: page,
              per_page: per_page,
              total: total,
              total_pages: (total.to_f / per_page).ceil,
            },
          }
        else
          @workflows = scope
          render json: @workflows.as_json(include: :workflow_steps)
        end
      end

      # ---------------------------------------------------------
      # 2. THE HTML PAGE RESPONSE (For initial browser loads)
      # ---------------------------------------------------------
      format.html do
        scope = Workflow.all.order(created_at: :desc)
        total = scope.count
        workflows_page = scope.limit(per_page).offset((page - 1) * per_page)

        @workflows_json = workflows_page.map do |wf|
          {
            id: wf.id,
            name: wf.name,
            description: wf.description,
            status: wf.status,
            trigger_type: wf.trigger_type,
            step_count: wf.workflow_steps.count,
            last_modified_by: User.find_by(id: wf.updated_by_id)&.full_name || "Admin",
            updated_at: wf.updated_at.strftime("%b %d, %Y %H:%M"),
          }
        end.to_json

        @workflows_json = "[]" if @workflows_json.blank?
        @workflows_pagination_json = {
          page: page,
          per_page: per_page,
          total: total,
          total_pages: (total.to_f / per_page).ceil,
        }.to_json
        # Rails automatically renders app/views/workflows/index.html.erb here
      end
    end
  end

  # GET /workflows/dashboard
  def dashboard
    @active_view = "My Tasks"
    # Rails will automatically render app/views/workflows/dashboard.html.erb
  end

  # GET /workflows/:id.json
  def show
    @workflow = Workflow.includes(:workflow_steps).find(params[:id])

    # This guarantees the payload will have a "workflow_steps" array
    render json: @workflow.as_json(include: :workflow_steps)
  end

  # POST /workflows
  def create
    @workflow = Workflow.new(workflow_params)
    @workflow.created_by_id = current_user.id
    @workflow.updated_by_id = current_user.id

    if @workflow.save
      render json: { success: true, workflow: @workflow }, status: :created
    else
      render json: { success: false, errors: @workflow.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /workflows/:id
  def update
    if @workflow.update(workflow_params)
      @workflow.update(updated_by_id: current_user.id)
      render json: { success: true, workflow: @workflow.as_json(include: :workflow_steps) }
    else
      render json: { success: false, errors: @workflow.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /workflows/:id
  def destroy
    if @workflow.destroy
      render json: { success: true, message: "Workflow deleted" }
    else
      render json: { success: false, errors: [ "Could not delete workflow" ] }, status: :unprocessable_entity
    end
  end

  # PATCH /workflows/:id/toggle_status
  def toggle_status
    new_status = @workflow.active? ? :inactive : :active
    if @workflow.update(status: new_status, updated_by_id: current_user.id)
      render json: { success: true, status: @workflow.status }
    else
      render json: { success: false, errors: @workflow.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def set_workflow
    @workflow = Workflow.find(params[:id])
  end

  def workflow_params
    # Permit all the standard flat attributes and known arrays.
    # Note: fallback_assignee_type / fallback_assignee_id are intentionally
    # omitted from the workflow-level params — escalation is now managed per
    # step via workflow_steps_attributes (see below).
    permitted = params.require(:workflow).permit(
      :name,
      :description,
      :status,
      :trigger_type,
      :folder_scope,
      target_folder_ids: [],
      exclude_folder_ids: [],
      workflow_steps_attributes: [
        :id,
        :title,
        :description,
        :position,
        :step_type,
        :node_type,
        :assignee_type,
        :assignee_id,
        :fallback_assignee_type,
        :fallback_assignee_id,
        :logic,
        :deadline_days,
        :_destroy,
        { step_config: {} },
      ],
      # `graph_data` is a JSONB column that stores the full React Flow canvas
      # (nodes, edges, viewport). It's an intentionally free-form document, so
      # we permit it explicitly via strong parameters (rather than reading the
      # raw, unpermitted hash with `to_unsafe_h`) — this keeps the mass
      # assignment restricted to the single `graph_data` attribute and avoids
      # bypassing ActionController::Parameters filtering entirely.
      graph_data: {}
    )

    permitted
  end
end
