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

            # 4. Optional: Archive the asset via soft-delete
            instance.asset.update!(deleted_at: Time.current)
          end
        end

        render json: { success: true }
      end

      # GET /api/v1/workflows/dashboard
      def dashboard
        per_page = 10

        my_tasks_page = [ params[:my_tasks_page].to_i, 1 ].max
        active_page    = [ params[:active_page].to_i, 1 ].max
        completed_page = [ params[:completed_page].to_i, 1 ].max

        my_tasks_scope = WorkflowTask.includes(workflow_instance: :asset, workflow_step: [])
                               .where(user: current_user, status: "pending")
                               .order(created_at: :desc)
        my_tasks_total = my_tasks_scope.count
        my_tasks = my_tasks_scope.limit(per_page).offset((my_tasks_page - 1) * per_page)

        active_scope = WorkflowInstance.includes(:asset, :workflow, :current_step)
                                           .where(status: "in_progress")
                                           .order(started_at: :desc)
        active_total = active_scope.count
        active_instances = active_scope.limit(per_page).offset((active_page - 1) * per_page)

        completed_scope = WorkflowInstance.includes(:workflow, :asset)
                                              .where(status: [ "completed", "rejected", "canceled" ])
                                              .order(completed_at: :desc)
        completed_total = completed_scope.count
        completed_instances = completed_scope.limit(per_page).offset((completed_page - 1) * per_page)

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
          pagination: {
            my_tasks: pagination_meta(my_tasks_page, per_page, my_tasks_total),
            active_workflows: pagination_meta(active_page, per_page, active_total),
            completed_workflows: pagination_meta(completed_page, per_page, completed_total),
          },
        }
      end

      private

      def pagination_meta(page, per_page, total)
        {
          page: page,
          per_page: per_page,
          total: total,
          total_pages: [ (total.to_f / per_page).ceil, 1 ].max,
        }
      end

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
