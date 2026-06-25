# config/initializers/smtp_loader.rb
#
# This initializer dynamically applies SMTP credentials from the settings table
# after the Rails environment is fully initialized.
#
# It includes defensive rescue hooks to prevent bootstrap failures when running
# initial database migrations, asset precompilation, or container builds.

Rails.application.config.after_initialize do
  # Establish active connection check to prevent errors on pristine database boots
  if ActiveRecord::Base.connection.active? && ActiveRecord::Base.connection.table_exists?("settings")
    Setting.apply_smtp_settings!
    Rails.logger.info "SMTP Dynamic Configuration: Successfully initialized system ActionMailer override."
  else
    Rails.logger.warn "SMTP Dynamic Configuration: Deferred (settings table or connection unavailable)."
  end
rescue ActiveRecord::NoDatabaseError, PG::ConnectionBad, ActiveRecord::PendingMigrationError => e
  # Keep the initialization loop clean and non-blocking during deployments/migrations
  Rails.logger.warn "SMTP Dynamic Configuration: Standby state active. Reason: #{e.class.name}"
end
