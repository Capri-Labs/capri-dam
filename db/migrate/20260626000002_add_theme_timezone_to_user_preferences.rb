# Adds UI theme and timezone to the per-user preference record.
#
# theme    — 'light' | 'dark' | 'system'  (default: 'system')
# timezone — IANA timezone string          (default: 'UTC')
class AddThemeTimezoneToUserPreferences < ActiveRecord::Migration[8.1]
  def change
    add_column :user_preferences, :theme,    :string, default: "system", null: false
    add_column :user_preferences, :timezone, :string, default: "UTC",    null: false
  end
end

