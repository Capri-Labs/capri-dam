# Per-user preference settings.
#
# Automatically created with defaults when a User is created.
# Stores notification opt-ins, language preference, and UI theme.
#
# Timezone is stored in the database (for internal timestamp display) but is
# intentionally NOT exposed to the user-facing profile UI — it is set to the
# server default ('Etc/UTC') and never accepted via the public API.
#
# @see User
class UserPreference < ApplicationRecord
  belongs_to :user

  SUPPORTED_LANGUAGES = %w[en de fr es pt nl ja zh ko].freeze
  SUPPORTED_THEMES    = %w[light dark system].freeze

  validates :language, inclusion: { in: SUPPORTED_LANGUAGES,
                                    message: "%{value} is not a supported language code" },
                       allow_blank: true

  validates :theme, inclusion: { in: SUPPORTED_THEMES,
                                 message: "%{value} is not a supported theme" },
                    allow_blank: true
end
