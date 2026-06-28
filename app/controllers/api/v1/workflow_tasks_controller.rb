module Api
  module V1
    class WorkflowTasksController < ApplicationController
      include AssetUrlHelper
      before_action :authenticate_hybrid!

      # POST /api/v1/workflow_tasks/:id/submit
      def submit
        task = WorkflowTask.find(params[:id])

        # Security: Ensure the user submitting is the one assigned to the task
        if task.user_id != current_user.id
          return render json: { error: "Unauthorized" }, status: :forbidden
        end

        # Ensure we aren't updating a task that was already completed or canceled
        if task.status != "pending"
          return render json: { error: "Task is no longer pending" }, status: :unprocessable_entity
        end

        # Save the decision and the audit comment
        task.update!(
          status: params[:decision], # 'approved' or 'rejected'
          comment: params[:comment],
          completed_at: Time.current
        )

        # Fire the Event Engine!
        WorkflowEngineWorker.perform_async(task.id)

        render json: { success: true, message: "Decision recorded" }
      end

      # POST /api/v1/workflows/bulk_stop
      def bulk_stop
        # 1. Find the instances
        instances = WorkflowInstance.where(id: params[:ids])

        ActiveRecord::Base.transaction do
          instances.each do |instance|
            # 2. Halt the engine
            instance.update!(
              status: "canceled", # Use 'canceled' to denote admin intervention
              completed_at: Time.current
            )

            # 3. Cancel all associated pending tasks
            instance.workflow_tasks.where(status: "pending").update_all(
              status: "canceled",
              comment: "Admin Action: Workflow manually stopped by #{current_user.email}",
              completed_at: Time.current
            )

            # 4. Optional: Reset asset status
            instance.asset.update!(status: "archived")
          end
        end

        render json: { success: true }
      end

      # GET /api/v1/workflows/dashboard
      def dashboard
        my_tasks = WorkflowTask.includes(workflow_instance: :asset, workflow_step: [])
                               .where(user: current_user, status: "pending")
                               .order(created_at: :desc)

        active_instances = WorkflowInstance.includes(:asset, :workflow, :current_step)
                                           .where(status: "in_progress")
                                           .order(started_at: :desc)

        completed_instances = WorkflowInstance.includes(:workflow, :asset)
                                              .where(status: [ "completed", "rejected", "canceled" ])
                                              .order(completed_at: :desc)
                                              .limit(50)

        completed_data = completed_instances.map do |instance|
          {
            instance_id: instance.id,
            workflow_name: instance.workflow.name,
            asset_id: instance.asset_id,
            asset_name: instance.asset.title.presence || "Untitled Asset",
            status: instance.status,
            completed_at: instance.completed_at || instance.updated_at,
          }
        end

        render json: {
          my_tasks: my_tasks.map { |t| format_task(t) },
          active_workflows: active_instances.map { |i| format_instance(i) },
          completed_workflows: completed_data,
        }
      end

      private


      def format_task(task)
        asset = task.workflow_instance.asset
        {
          task_id: task.id,
          step_title: task.workflow_step.title,
          asset_id: asset.id,
          asset_name: asset.title,
          asset_thumb: asset_url_for(asset),
          assigned_at: task.created_at,
        }
      end

      def format_instance(instance)
        asset = instance.asset
        {
          instance_id: instance.id,
          workflow_name: instance.workflow.name,
          current_step: instance.current_step&.title || "Processing",
          asset_id: asset.id,
          asset_name: asset.title,
          started_at: instance.started_at,
        }
      end
    end
  end
end
