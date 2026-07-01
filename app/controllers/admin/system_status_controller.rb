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
    # Convert parameters to hash cleanly
    Setting.set("smtp_settings", smtp_params.to_h)
    # Re-apply config changes to the current environment context
    Setting.apply_smtp_settings!
    render json: { success: true, message: "SMTP configuration updated successfully." }
  end

  # POST /admin/system_status/test_email
  def test_email
    recipient = params[:test_recipient]
    if recipient.blank?
      return render json: { success: false, error: "Recipient email is required." }, status: :unprocessable_entity
    end

    begin
      Setting.apply_smtp_settings!
      AdminMailer.test_connection_email(recipient).deliver_now
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
      :authentication, :enable_starttls_auto, :sender_address
    )
  end

  def diagnostic_report
    {
      app_server: {
        status: "healthy",
        environment: Rails.env,
        rails_version: Rails.version,
        ruby_version: RUBY_VERSION,
        uptime: system_uptime,
      },
      database: db_diagnostics,
      cache_queue: redis_and_sidekiq_diagnostics,
      storage_backend: active_storage_diagnostics,
    }
  end

  def system_uptime
    `uptime`.strip rescue "Unavailable"
  end

  def db_diagnostics
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    connected = ActiveRecord::Base.connection.active?
    latency = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(2)

    {
      status: connected ? "healthy" : "offline",
      latency_ms: latency,
      adapter: ActiveRecord::Base.connection.adapter_name,
      pool_size: ActiveRecord::Base.connection.pool.size,
      active_connections: ActiveRecord::Base.connection.pool.stat[:connections],
    }
  rescue => e
    { status: "offline", error: e.message }
  end

  def redis_and_sidekiq_diagnostics
    require "sidekiq/api"

    redis_info = nil
    redis_connected = false
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    Sidekiq.redis do |conn|
      redis_info = conn.info
      redis_connected = true
    end

    latency = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(2)
    stats = Sidekiq::Stats.new

    {
      status: "healthy",
      latency_ms: latency,
      redis_version: redis_info&.dig("redis_version") || "Unknown",
      queue_depth: stats.enqueued,
      processed: stats.processed,
      failed: stats.failed,
      active_workers: Sidekiq::Workers.new.size,
      processes: Sidekiq::ProcessSet.new.size,
    }
  rescue => e
    { status: "degraded", error: "Sidekiq/Redis offline. Details: #{e.message}" }
  end

  def active_storage_diagnostics
    service = ActiveStorage::Blob.service
    test_key = "healthcheck-#{SecureRandom.uuid}.txt"

    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    service.upload(test_key, StringIO.new("1"))
    service.download(test_key)
    service.delete(test_key)
    latency = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(2)

    {
      status: "healthy",
      provider: service.class.name.demodulize,
      latency_ms: latency,
    }
  rescue => e
    { status: "unreachable", error: "Storage driver error: #{e.message}" }
  end
end
