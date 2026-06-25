# Per-user preference settings.
#
# Automatically created with defaults when a User is created.
# Stores notification opt-ins, language preference, and future UI settings.
#
# @see User
class UserPreference < ApplicationRecord
  belongs_to :user

  SUPPORTED_LANGUAGES = %w[en de fr es pt nl ja zh ko].freeze

  validates :language, inclusion: { in: SUPPORTED_LANGUAGES,
                                    message: "%{value} is not a supported language code" },
                       allow_blank: true
end

