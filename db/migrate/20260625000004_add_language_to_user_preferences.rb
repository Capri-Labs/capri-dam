# Adds language preference column to user_preferences.
#
# Stored as a BCP-47 locale string (e.g. "en", "de", "fr").
# Defaults to "en" which matches the existing application locale default.
class AddLanguageToUserPreferences < ActiveRecord::Migration[8.1]
  def change
    add_column :user_preferences, :language, :string, default: 'en', null: false
  end
end

