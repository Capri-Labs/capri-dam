# Per-user preference settings.
#
# Automatically created with defaults when a User is created.
# Stores notification opt-ins, language preference, UI theme, and timezone.
#
# @see User
class UserPreference < ApplicationRecord
  belongs_to :user

  SUPPORTED_LANGUAGES = %w[en de fr es pt nl ja zh ko].freeze
  SUPPORTED_THEMES    = %w[light dark system].freeze
  # A curated subset of commonly-used IANA timezones.
  SUPPORTED_TIMEZONES = ActiveSupport::TimeZone.all.map(&:tzinfo).map(&:name).freeze

  validates :language, inclusion: { in: SUPPORTED_LANGUAGES,
                                    message: "%{value} is not a supported language code" },
                       allow_blank: true

  validates :theme, inclusion: { in: SUPPORTED_THEMES,
                                 message: "%{value} is not a supported theme" },
                    allow_blank: true

  validates :timezone, inclusion: { in: SUPPORTED_TIMEZONES,
                                    message: "%{value} is not a valid IANA timezone" },
                       allow_blank: true
end
