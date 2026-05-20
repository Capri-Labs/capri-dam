class Admin::EmailDeliveriesController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_admin!

  # GET /admin/email_deliveries
  def index
    # We load the template association to display the template name in the UI,
    # and default to showing the most recent 100 logs.
    logs = EmailDelivery.includes(:email_template)
                        .order(created_at: :desc)
                        .limit(100)

    # Optional: Filter by status if the React UI sends `?status=failed`
    logs = logs.where(status: params[:status]) if params[:status].present?

    formatted_logs = logs.map do |log|
      {
        id: log.id,
        recipient: log.recipient_email,
        template_name: log.email_template&.name || 'Deleted Template',
        status: log.status,
        retry_count: log.retry_count,
        error_log: log.error_log,
        sent_at: log.created_at.strftime("%Y-%m-%d %H:%M:%S")
      }
    end

    render json: { email_deliveries: formatted_logs }
  end

  # POST /admin/email_deliveries/:id/retry
  def retry
    delivery = EmailDelivery.find(params[:id])

    if delivery.status == 'sent'
      render json: { success: false, errors: ["This email has already been successfully sent."] }
      return
    end

    # Reset the log and throw it back into the Sidekiq queue
    delivery.update!(
      status: 'pending',
      retry_count: 0,
      error_log: nil
    )

    EmailDispatcherWorker.perform_async(delivery.id)

    render json: { success: true, message: "Email manually queued for retry." }
  end

  private

  def ensure_admin!
    render json: { error: "Unauthorized" }, status: :forbidden unless current_user.admin?
  end
end