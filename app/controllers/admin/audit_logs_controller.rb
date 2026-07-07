class Admin::AuditLogsController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_admin!

  # GET /admin/audit_logs
  #
  # Browse/search the immutable audit trail. Supports filtering by actor,
  # true (impersonating) actor, action, the auditable resource type, whether
  # the action happened while impersonating, and a created_at date range.
  def index
    logs = AuditLog.includes(:user, :true_user).order(created_at: :desc)
    logs = logs.where(user_id: params[:user_id]) if params[:user_id].present?
    # NOTE: intentionally named `audit_action` (not `action`) — `action` is a
    # reserved Rails routing param (always equal to the controller action
    # name, e.g. "index"), so a query filter literally named `action` would
    # silently shadow it and never match any real audit log row.
    logs = logs.where(action: params[:audit_action]) if params[:audit_action].present?
    logs = logs.where(auditable_type: params[:auditable_type]) if params[:auditable_type].present?
    logs = logs.where(impersonated: ActiveModel::Type::Boolean.new.cast(params[:impersonated])) if params[:impersonated].present?
    logs = logs.where("created_at >= ?", Time.zone.parse(params[:date_from]).beginning_of_day) if params[:date_from].present?
    logs = logs.where("created_at <= ?", Time.zone.parse(params[:date_to]).end_of_day) if params[:date_to].present?

    if params[:search].present?
      term = "%#{params[:search].strip}%"
      logs = logs.joins(:user).where("users.email ILIKE ? OR audit_logs.auditable_type ILIKE ? OR audit_logs.action ILIKE ?", term, term, term)
    end

    per_page = params.fetch(:per_page, 25).to_i.clamp(1, 100)
    page = [ params.fetch(:page, 1).to_i, 1 ].max
    total = logs.count
    entries = logs.offset((page - 1) * per_page).limit(per_page)

    render json: {
      audit_logs: entries.map { |log| serialize_log(log) },
      pagination: {
        page: page,
        per_page: per_page,
        total: total,
        total_pages: (total.to_f / per_page).ceil,
      },
      # Populates the "Action" / "Resource Type" filter dropdowns without a
      # second round-trip.
      filter_options: {
        actions: AuditLog.distinct.order(:action).pluck(:action),
        auditable_types: AuditLog.distinct.order(:auditable_type).pluck(:auditable_type),
      },
    }
  end

  private

  def serialize_log(log)
    {
      id: log.id,
      action: log.action,
      auditable_type: log.auditable_type,
      auditable_id: log.auditable_id,
      changes_data: log.changes_data,
      impersonated: log.impersonated,
      ip_address: log.ip_address,
      user_agent: log.user_agent,
      created_at: log.created_at.iso8601,
      user: log.user && { id: log.user.id, email: log.user.email, name: log.user.name },
      true_user: log.true_user && { id: log.true_user.id, email: log.true_user.email, name: log.true_user.name },
    }
  end

  def ensure_admin!
    render json: { error: "Unauthorized" }, status: :forbidden unless current_user.admin?
  end
end
