class Admin::SystemConfigurationsController < ApplicationController
  # Assuming you have admin authentication in place via an inherited controller
  # like Admin::BaseController, or a before_action here:
  # before_action :authenticate_admin!

  def logging_status
    # Fetch the global log level, or initialize a default representation if it doesn't exist yet
    config = SystemConfiguration.find_or_initialize_by(key: 'global_log_level')

    # If it's a new record, provide sensible defaults for the UI
    if config.new_record?
      config.assign_attributes(
        data_type: 'string',
        value: 'INFO',
        fallback_value: 'INFO',
        description: 'Global operational trace filter.'
      )
    end

    render json: {
      success: true,
      current_level: config.value,
      fallback_level: config.fallback_value,
      expires_at: config.expires_at,
      # Calculate remaining minutes for the UI progress bar, if TTL is active
      ttl_active: config.expires_at.present? && config.expires_at > Time.current,
      minutes_remaining: calculate_remaining_minutes(config.expires_at)
    }
  end

  def update_logging
    config = SystemConfiguration.find_or_initialize_by(key: 'global_log_level')

    new_level = params[:level].to_s.upcase
    ttl_minutes = params[:ttl_minutes].to_i

    # Ensure we only accept valid Ruby Logger levels
    valid_levels = %w[DEBUG INFO WARN ERROR FATAL]
    unless valid_levels.include?(new_level)
      return render json: { success: false, error: "Invalid log level provided." }, status: :unprocessable_entity
    end

    # Configure the Time-To-Live (TTL)
    expiration = ttl_minutes > 0 ? ttl_minutes.minutes.from_now : nil
    fallback = ttl_minutes > 0 ? (config.fallback_value || 'INFO') : nil

    if config.update(
      data_type: 'string',
      value: new_level,
      expires_at: expiration,
      fallback_value: fallback,
      updated_by_id: current_user&.id # Assuming current_user is available
    )
      # Note: The Redis Pub/Sub broadcast happens automatically via the after_commit callback on the model!
      render json: {
        success: true,
        message: "Log level updated to #{new_level}.",
        expires_at: expiration
      }
    else
      render json: {
        success: false,
        error: config.errors.full_messages.join(', ')
      }, status: :unprocessable_entity
    end
  end

  private

  def calculate_remaining_minutes(expires_at)
    return 0 unless expires_at && expires_at > Time.current
    ((expires_at - Time.current) / 60).round
  end
end