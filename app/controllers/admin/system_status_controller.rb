class Admin::SystemStatusController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_admin!

  # GET /admin/system_status
  def index
    @smtp_config = Setting.get("smtp_settings")
    @notification_rules = Setting.get("notification_rules")

    # UI view point
    @active_view = "System Operations"

    respond_to do |format|
      format.html
      format.json { render json: diagnostic_report }
    end
  end

  # POST /admin/system_status/update_smtp
  def update_smtp
    config = build_config_from_params

    unless config.valid?
      return render json: { success: false, errors: config.errors.full_messages }, status: :unprocessable_entity
    end

    if config.enabled
      validation = SmtpConnectionValidator.new(config).call
      unless validation.success?
        return render json: {
          success: false,
          error_code: validation.error_code,
          error: "SMTP handshake failed: #{validation.message}",
        }, status: :unprocessable_entity
      end
    end

    config.persist!
    render json: { success: true, message: "SMTP configuration updated successfully." }
  end

  # POST /admin/system_status/test_connection
  #
  # Pre-flight, non-blocking connection validation only -- performs a raw
  # SMTP handshake against the submitted (not-yet-saved) parameters without
  # sending any email. Used by both the "Test Connection" button and as a
  # guard inside #update_smtp before persisting new credentials.
  def test_connection
    config = build_config_from_params

    unless config.valid?
      return render json: {
        success: false,
        error_code: "INVALID_CONFIGURATION",
        error: config.errors.full_messages.to_sentence,
      }, status: :unprocessable_entity
    end

    result = SmtpConnectionValidator.new(config).call
    if result.success?
      render json: { success: true, message: "SMTP handshake succeeded. Connection is reachable and authenticated." }
    else
      render json: { success: false, error_code: result.error_code, error: result.message }, status: :unprocessable_entity
    end
  end

  # POST /admin/system_status/test_email
  def test_email
    recipient = params[:test_recipient]
    if recipient.blank?
      return render json: { success: false, error: "Recipient email is required." }, status: :unprocessable_entity
    end

    begin
      CentralNotificationMailer.build_admin_test_mail(recipient).deliver_now
      render json: { success: true, message: "Test connection successful. Email sent to #{recipient}." }
    rescue => e
      render json: { success: false, error: "SMTP Error: #{e.message}" }, status: :internal_server_error
    end
  end

  # POST /admin/system_status/restart_server
  def restart_server
    restart_file = Rails.root.join("tmp/restart.txt")
    begin
      FileUtils.mkdir_p(File.dirname(restart_file))
      FileUtils.touch(restart_file)
      render json: { success: true, message: "Soft restart triggered successfully via tmp/restart.txt." }
    rescue => e
      render json: { success: false, error: "Failed to write restart trigger: #{e.message}" }, status: :internal_server_error
    end
  end

  private

  def ensure_admin!
    unless current_user.admin?
      render json: { error: "Unauthorized access" }, status: :forbidden
    end
  end

  def smtp_params
    params.require(:smtp_config).permit(
      :enabled, :address, :port, :domain, :user_name, :password,
      :authentication, :enable_starttls_auto, :sender_address,
      :sender_name, :security_protocol
    )
  end

  # Builds a SystemEmailConfig from the submitted params, transparently
  # keeping the existing stored password when the UI sends back the masked
  # placeholder instead of a real secret.
  def build_config_from_params
    config = SystemEmailConfig.from_raw(smtp_params.to_h)
    config.smtp_password = SystemEmailConfig.current.smtp_password if smtp_params[:password].to_s.strip == "********"
    config
  end

  # The System Observability payload. Delegated to {Observability::Report} —
  # the diagnostics grew past what belongs inline in a controller, and a
  # service can be exercised directly by a spec without a request.
  def diagnostic_report
    Observability::Report.call
  end
end
