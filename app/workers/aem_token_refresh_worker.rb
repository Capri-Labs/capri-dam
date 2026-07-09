
# Auto-refreshes IMS access tokens for JWT-based (Adobe AEM) connectors before
# they expire, so a live migration run never stalls mid-batch waiting on a
# manual "Refresh Token" click.
#
# Scheduled via `whenever` (see config/schedule.rb) — runs every 10 minutes,
# refreshing any jwt_service_account connector whose cached token is missing
# or expiring within SystemConnector::TOKEN_REFRESH_BUFFER.
#
# Failures are recorded on the connector (token_status="error",
# last_token_error) rather than raised, so one bad connector never blocks the
# refresh sweep for the others.
class AemTokenRefreshWorker
  include Sidekiq::Worker

  sidekiq_options queue: "default", retry: 2

  def perform
    SystemConnector.where(credential_type: "jwt_service_account").find_each do |connector|
      next if connector.token_valid?

      begin
        connector.refresh_access_token!
        Rails.logger.info("[AemTokenRefreshWorker] refreshed token for connector##{connector.id}")
      rescue => e
        Rails.logger.warn("[AemTokenRefreshWorker] failed to refresh connector##{connector.id}: #{e.message}")
      end
    end
  end
end
