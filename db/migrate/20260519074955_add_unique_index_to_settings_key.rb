class AddUniqueIndexToSettingsKey < ActiveRecord::Migration[8.1]
  def change
    # Ensure key is unique at the database level to prevent duplicate config records
    add_index :settings, :key, unique: true unless index_exists?(:settings, :key)
  end
end
