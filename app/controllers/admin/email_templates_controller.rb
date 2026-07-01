class Admin::EmailTemplatesController < ApplicationController
  SYSTEM_EVENTS = [
    {
      id: "user_created",
      label: "User Provisioned (Welcome)",
      category: "transactional",
      variables: %w[user.first_name user.email user.temp_password],
    },
    {
      id: "user_suspended",
      label: "Account Suspended",
      category: "transactional",
      variables: %w[user.first_name user.email],
    },
    {
      id: "workflow_requested",
      label: "Workflow: Approval Requested",
      category: "notification",
      variables: %w[user.first_name asset.name folder.name workflow.url],
    },
    {
      id: "workflow_approved",
      label: "Workflow: Asset Approved",
      category: "notification",
      variables: %w[user.first_name asset.name reviewer.name asset.url],
    },
    {
      id: "workflow_rejected",
      label: "Workflow: Asset Rejected",
      category: "notification",
      variables: %w[user.first_name asset.name reviewer.notes asset.url],
    },
    {
      id: "user_mentioned",
      label: "User @Mentioned",
      category: "mention",
      variables: %w[recipient.first_name sender.name mention.text context.url],
    },
    {
      id: "asset_published",
      label: "Asset Published",
      category: "notification",
      variables: %w[asset.name asset.url published_by.name],
    },
    {
      id: "asset_uploaded",
      label: "Asset Uploaded to Folder",
      category: "notification",
      variables: %w[asset.name folder.name uploaded_by.name],
    },
    {
      id: "collection_shared",
      label: "Collection Shared With You",
      category: "announcement",
      variables: %w[collection.name shared_by.name collection.url],
    },
    {
      id: "report_ready",
      label: "Report Generation Complete",
      category: "system",
      variables: %w[report.name report.download_url generated_at],
    },
    {
      id: "storage_warning",
      label: "Storage Quota Warning",
      category: "system",
      variables: %w[used_gb quota_gb percent_used],
    },
    {
      id: "system_maintenance",
      label: "Scheduled Maintenance",
      category: "announcement",
      variables: %w[maintenance_start maintenance_end message],
    },
  ].freeze

  before_action :authenticate_user!
  before_action :ensure_admin!
  before_action :set_template, only: %i[show update destroy send_test]

  def index
    @active_view = "Email Engine"

    respond_to do |format|
      format.html
      format.json do
        templates = EmailTemplate.order(created_at: :desc).map { |template| serialize_template(template) }
        render json: { email_templates: templates }
      end
    end
  end

  def show
    render json: { email_template: serialize_template(@template, full: true) }
  end

  def create
    @template = EmailTemplate.new(template_params.merge(created_by_id: current_user.id))

    if @template.save
      render json: { success: true, message: "Template created successfully.", email_template: serialize_template(@template, full: true) }
    else
      render json: { success: false, errors: @template.errors.full_messages }
    end
  end

  def update
    if @template.update(template_params)
      render json: { success: true, message: "Template saved.", email_template: serialize_template(@template, full: true) }
    else
      render json: { success: false, errors: @template.errors.full_messages }
    end
  end

  def destroy
    if @template.destroy
      render json: { success: true, message: "Template removed." }
    else
      render json: { success: false, errors: [ "Failed to delete template." ] }
    end
  end

  def event_triggers
    render json: { events: SYSTEM_EVENTS }
  end

  def send_test
    payload = params[:payload].presence || @template.preview_data.presence || {}
    recipient_email = params[:recipient_email].presence || current_user.email
    delivery = EmailDelivery.create!(
      email_template: @template,
      recipient_email: recipient_email,
      payload: payload.deep_stringify_keys,
      status: "pending"
    )
    EmailDispatcherWorker.perform_async(delivery.id)

    render json: { success: true, message: "Test email queued.", delivery_id: delivery.id }
  end

  private

  def set_template
    @template = EmailTemplate.find(params[:id])
  end

  def template_params
    permitted = params.require(:email_template).permit(
      :name,
      :event_trigger,
      :subject,
      :html_body,
      :text_body,
      :active,
      :description,
      :category,
      variables: {},
      preview_data: {}
    )

    permitted[:variables] ||= {}
    permitted[:preview_data] ||= {}
    permitted
  end

  def serialize_template(template, full: false)
    data = {
      id: template.id,
      name: template.name,
      event_trigger: template.event_trigger,
      subject: template.subject,
      active: template.active,
      category: template.category,
      description: template.description,
      variables: template.variables,
      preview_data: template.preview_data,
      updated_at: template.updated_at.strftime("%Y-%m-%d %H:%M"),
    }

    return data unless full

    data.merge(
      html_body: template.html_body,
      text_body: template.text_body,
      created_by_id: template.created_by_id,
      created_at: template.created_at,
      updated_at: template.updated_at
    )
  end

  def ensure_admin!
    render json: { error: "Unauthorized" }, status: :forbidden unless current_user.admin?
  end
end
