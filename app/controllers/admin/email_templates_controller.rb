class Admin::EmailTemplatesController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_admin!
  before_action :set_template, only: [:show, :update, :destroy]

  # GET /admin/email_templates
  def index
    @active_view = 'Email Engine'

    respond_to do |format|
      format.html # Renders the React layout
      format.json do
        templates = EmailTemplate.order(created_at: :desc).map do |template|
          {
            id: template.id,
            name: template.name,
            event_trigger: template.event_trigger,
            subject: template.subject,
            active: template.active,
            updated_at: template.updated_at.strftime("%Y-%m-%d %H:%M")
          }
        end
        render json: { email_templates: templates }
      end
    end
  end

  # GET /admin/email_templates/:id
  def show
    render json: { email_template: @template }
  end

  # POST /admin/email_templates
  def create
    @template = EmailTemplate.new(template_params)

    if @template.save
      render json: { success: true, message: "Template created successfully." }
    else
      render json: { success: false, errors: @template.errors.full_messages }
    end
  end

  # PATCH /admin/email_templates/:id
  def update
    if @template.update(template_params)
      render json: { success: true, message: "Template saved." }
    else
      render json: { success: false, errors: @template.errors.full_messages }
    end
  end

  # DELETE /admin/email_templates/:id
  def destroy
    if @template.destroy
      render json: { success: true, message: "Template removed." }
    else
      render json: { success: false, errors: ["Failed to delete template."] }
    end
  end

  private

  def set_template
    @template = EmailTemplate.find(params[:id])
  end

  def template_params
    params.require(:email_template).permit(:name, :event_trigger, :subject, :html_body, :text_body, :active)
  end

  def ensure_admin!
    render json: { error: "Unauthorized" }, status: :forbidden unless current_user.admin?
  end
end