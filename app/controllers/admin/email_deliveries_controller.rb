class Admin::EmailDeliveriesController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_admin!

  def index
    deliveries = EmailDelivery.includes(:email_template).order(created_at: :desc)
    deliveries = deliveries.where(status: params[:status]) if params[:status].present?
    deliveries = deliveries.where("recipient_email ILIKE ?", "%#{params[:search].strip}%") if params[:search].present?
    deliveries = deliveries.where("created_at >= ?", Time.zone.parse(params[:date_from]).beginning_of_day) if params[:date_from].present?
    deliveries = deliveries.where("created_at <= ?", Time.zone.parse(params[:date_to]).end_of_day) if params[:date_to].present?

    per_page = params.fetch(:per_page, 25).to_i.clamp(1, 100)
    page = [ params.fetch(:page, 1).to_i, 1 ].max
    total = deliveries.count
    logs = deliveries.offset((page - 1) * per_page).limit(per_page)

    render json: {
      email_deliveries: logs.map { |delivery| serialize_delivery(delivery) },
      pagination: {
        page: page,
        per_page: per_page,
        total: total,
        total_pages: (total.to_f / per_page).ceil,
      },
    }
  end

  def retry
    delivery = EmailDelivery.find(params[:id])

    if delivery.status == "sent"
      render json: { success: false, errors: [ "This email has already been successfully sent." ] }
      return
    end

    reset_delivery!(delivery)
    EmailDispatcherWorker.perform_async(delivery.id)

    render json: { success: true, message: "Email manually queued for retry." }
  end

  def bulk_retry_failed
    deliveries = EmailDelivery.where(status: "failed")
    retried_count = deliveries.count

    deliveries.find_each do |delivery|
      reset_delivery!(delivery)
      EmailDispatcherWorker.perform_async(delivery.id)
    end

    render json: { success: true, retried_count: retried_count }
  end

  def stats
    scope = EmailDelivery.all
    render json: {
      total: scope.count,
      sent: scope.sent.count,
      failed: scope.failed.count,
      pending: scope.pending.count,
      today: scope.where(created_at: Time.zone.today.all_day).count,
      this_week: scope.where(created_at: Time.zone.now.all_week).count,
    }
  end

  private

  def serialize_delivery(delivery)
    {
      id: delivery.id,
      recipient: delivery.recipient_email,
      template_name: delivery.email_template&.name || "Deleted Template",
      status: delivery.status,
      retry_count: delivery.retry_count,
      error_log: delivery.error_log,
      sent_at: delivery.created_at.strftime("%Y-%m-%d %H:%M:%S"),
    }
  end

  def reset_delivery!(delivery)
    delivery.update!(status: "pending", retry_count: 0, error_log: nil)
  end

  def ensure_admin!
    render json: { error: "Unauthorized" }, status: :forbidden unless current_user.admin?
  end
end
