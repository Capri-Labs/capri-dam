class WorkflowMailer < ApplicationMailer
  default from: -> { SystemEmailConfig.current.from_address_with_name }

  def task_assigned(task_id)
    @task = WorkflowTask.find(task_id)
    @user = @task.user
    @asset = @task.workflow_instance.asset

    # URL to the exact asset in the DAM (matches the /assets?id=UUID deep-link route)
    @action_url = "#{Rails.application.config.action_mailer.default_url_options[:host]}/assets?id=#{@asset.uuid || @asset.id}"

    mail(
      to: @user.email,
      subject: "Action Required: DAM Workflow Task Assigned (#{@task.workflow_step.title})"
    )
  end

  # Generic workflow alert triggered by the `email_notification` automated
  # action node (see WorkflowActionExecutor#send_email). Routed exclusively
  # through CentralNotificationMailer#deliver_workflow_alert.
  def workflow_email(to:, subject:, body:, cc: nil, priority: "normal")
    headers["X-Priority"] = priority_header(priority)

    mail(to: to, cc: cc.presence, subject: subject) do |format|
      format.html { render html: body.to_s.html_safe } # rubocop:disable Rails/OutputSafety
      format.text { render plain: ActionView::Base.full_sanitizer.sanitize(body.to_s) }
    end
  end

  private

  def priority_header(priority)
    case priority.to_s
    when "high" then "1 (Highest)"
    when "low" then "5 (Lowest)"
    else "3 (Normal)"
    end
  end
end
