module Workflows
  class WorkflowsController < ApplicationController
    before_action :authenticate_user!
    # Updated: Only include actions that actually exist in the controller
    before_action :set_workflow, only: [:update, :destroy, :toggle_status]

    # GET /workflows (For the list view)
    def index
      @workflows = Workflow.all.order(created_at: :desc)
      render json: @workflows.as_json(include: :workflow_steps)
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
end