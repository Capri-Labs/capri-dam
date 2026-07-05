# Centralized provider of "global" Liquid variables that are always available
# to every email template, regardless of which event triggered it (e.g.
# company/app branding, current date/year, support contact). Event-specific
# payloads always win over these defaults -- see `.with_defaults`.
class GlobalTemplateVariables
  # Flat list of dotted variable names surfaced in the Template Variables
  # picker (Admin::EmailTemplatesController#event_triggers) so template
  # authors can insert them regardless of the selected event trigger.
  NAMES = %w[
    company.name
    company.support_email
    company.address
    app.name
    app.url
    recipient.email
    current_year
    current_date
    unsubscribe_url
  ].freeze

  # Builds the default values hash (nested, string-keyed so it matches the
  # shape Liquid expects) used to seed new templates' preview data and to
  # backfill any keys a caller's payload does not already provide.
  def self.defaults
    email_config = SystemEmailConfig.current
    app_url = Rails.application.config.action_mailer.default_url_options&.dig(:host).presence || "https://app.example.com"
    app_url = "https://#{app_url}" unless app_url.start_with?("http")

    {
      "company" => {
        "name" => email_config.default_from_name.presence || "Capri DAM",
        "support_email" => email_config.default_from_address.presence || "support@capridam.com",
        "address" => "",
      },
      "app" => {
        "name" => "Capri DAM",
        "url" => app_url,
      },
      "current_year" => Date.current.year.to_s,
      "current_date" => Date.current.strftime("%B %d, %Y"),
      "unsubscribe_url" => "#{app_url}/settings/notifications",
    }
  end

  # Deep-merges the given payload on top of the global defaults so that any
  # event-specific value always takes precedence over the generic fallback.
  def self.with_defaults(payload)
    defaults.deep_merge(payload.deep_stringify_keys)
  end
end
