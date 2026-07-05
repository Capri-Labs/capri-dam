require "singleton"

# Single source of truth for dispatching every outbound system notification
# email (user registration/password-reset transport config, workflow alerts,
# workflow task assignments, admin SMTP test messages, and templated/audited
# EmailDelivery records). No other code should build an ActionMailer message
# directly against a locally-configured mailer -- everything is routed
# through this thread-safe singleton so the database-backed SystemEmailConfig
# is guaranteed to be applied before any transmission attempt.
class CentralNotificationMailer
  include Singleton

  class << self
    delegate :build_template_mail, :build_admin_test_mail, :deliver_workflow_task_assigned,
              :deliver_workflow_alert, to: :instance
  end

  # Applies the current database-backed SMTP configuration and builds a
  # DynamicMailer message for a rendered (Liquid) template payload. Returns
  # the Mail message so callers (e.g. EmailDispatcherWorker) retain control
  # over delivery, retries, and error handling.
  def build_template_mail(to:, subject:, html_body:, text_body:)
    apply_config!
    DynamicMailer.dispatch_email(to: to, subject: subject, html_body: html_body.to_s, text_body: text_body.to_s)
  end

  # Builds the administrator SMTP diagnostic email.
  def build_admin_test_mail(recipient)
    apply_config!
    AdminMailer.test_connection_email(recipient)
  end

  # Queues (deliver_later) the workflow task-assignment notification.
  def deliver_workflow_task_assigned(task_id)
    apply_config!
    WorkflowMailer.task_assigned(task_id).deliver_later
  end

  # Queues (deliver_later) an ad hoc workflow alert email raised by
  # WorkflowActionExecutor's `email_notification` automated action.
  def deliver_workflow_alert(to:, subject:, body:, cc: nil, priority: "normal")
    apply_config!
    WorkflowMailer.workflow_email(to: to, cc: cc, subject: subject, body: body, priority: priority).deliver_later
  end

  private

  # Re-applies the database-backed SMTP configuration to ActionMailer::Base
  # before every dispatch attempt, guaranteeing every notification -- no
  # matter which application segment triggered it -- uses the single
  # validated configuration surfaced at /settings/system.
  def apply_config!
    SystemEmailConfig.current.apply!
  end
end
