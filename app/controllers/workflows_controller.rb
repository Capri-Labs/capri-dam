class WorkflowsController < ApplicationController
  before_action :authenticate_user!
  # Updated: Only include actions that actually exist in the controller
  before_action :set_workflow, only: [:update, :destroy, :toggle_status]

  def index
    respond_to do |format|
      # ---------------------------------------------------------
      # 1. THE API RESPONSE (For React fetch requests)
      # ---------------------------------------------------------
      format.json do
        @workflows = Workflow.all.order(created_at: :desc)
        render json: @workflows.as_json(include: :workflow_steps)
      end

      # ---------------------------------------------------------
      # 2. THE HTML PAGE RESPONSE (For initial browser loads)
      # ---------------------------------------------------------
      format.html do
        @workflows_json = Workflow.all.map do |wf|
          {
            id: wf.id,
            name: wf.name,
            description: wf.description,
            status: wf.status,
            trigger_type: wf.trigger_type,
            step_count: wf.workflow_steps.count,
            last_modified_by: User.find_by(id: wf.updated_by_id)&.full_name || "Admin",
            updated_at: wf.updated_at.strftime("%b %d, %Y %H:%M")
          }
        end.to_json

        @workflows_json = "[]" if @workflows_json.blank?
        # Rails automatically renders app/views/workflows/index.html.erb here
      end
    end
  end

  # GET /workflows/dashboard
  def dashboard
    # This intentionally left empty.
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
      render json: { success: false, errors: ["Could not delete workflow"] }, status: :search_timeout
    end
  end

  # PATCH /workflows/:id/toggle_status
  def toggle_status
    new_status = @workflow.active? ? :inactive : :active
    if @workflow.update(status: new_status, updated_by_id: current_user.id)
      render json: { success: true, status: @workflow.status }
    else
      render json: { success: false }
    end
  end

  private

  def set_workflow
    @workflow = Workflow.find(params[:id])
  end

  def workflow_params
    params.require(:workflow).permit(
      :name,
      :description,
      :status,
      :trigger_type,
      :fallback_assignee_type,
      :fallback_assignee_id,
      workflow_steps_attributes: [
        :id,
        :title,
        :description,
        :position,
        :step_type,
        :assignee_type,
        :assignee_id,
        :logic,
        :deadline_days,
        :_destroy
      ]
    )
  end
end