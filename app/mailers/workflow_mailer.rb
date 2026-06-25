class WorkflowMailer < ApplicationMailer
  default from: "notifications@yourdam.com" # Update to your system's default sender

  def task_assigned(task_id)
    @task = WorkflowTask.find(task_id)
    @user = @task.user
    @asset = @task.workflow_instance.asset

    # URL to the exact asset in the DAM
    @action_url = "#{Rails.application.config.action_mailer.default_url_options[:host]}/dashboard?view=asset_explorer&asset=#{@asset.id}"

    mail(
      to: @user.email,
      subject: "Action Required: DAM Workflow Task Assigned (#{@task.workflow_step.title})"
    )
  end
end
