class TaskNotificationWorker
  include Sidekiq::Worker
  sidekiq_options queue: "notifications", retry: 3

  def perform(task_id)
    task = WorkflowTask.find_by(id: task_id)
    return unless task && task.status == "pending"

    user = task.user
    asset = task.workflow_instance.asset

    # 1. Create the In-App Notification Record
    Notification.create!(
      user: user,
      title: "New Task: #{task.workflow_step.title}",
      message: "Please review: #{asset.title || "Untitled Asset"}",
      # Deep link straight to the workflow dashboard
      action_url: "/workflows/dashboard"
    )

    # 2. Fire the Email via ActionMailer
    # (Deliver later uses ActiveJob/Sidekiq under the hood)
    WorkflowMailer.task_assigned(task.id).deliver_later
  rescue StandardError => e
    Rails.logger.error "💥 Failed to send notifications for Task #{task_id}: #{e.message}"
    raise e
  end
end
