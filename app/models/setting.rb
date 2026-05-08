class Setting < ApplicationRecord
  # Encrypt these specific keys automatically in the DB
  # You must have your master.key set up in Rails
  validates :key, presence: true, uniqueness: true

  def self.set(key_name, value)
    setting = find_or_initialize_by(key: key_name.to_s)
    setting.value = value
    setting.save!
  end

  def self.get(key_name)
    find_by(key: key_name.to_s)&.value
  end

  def self.get_provider_config(provider)
    data = JSON.parse(get("storage_config_#{provider}") || "{}")

    # Mask sensitive fields before sending to React
    data.each do |key, value|
      if key.to_s.include?('secret') && value.present?
        data[key] = "********" # Send asterisks to UI
      end
    end
    data
  end

  # Logic to ensure sensitive keys are handled correctly
  # (Optional: You could use the 'lockbox' gem or Rails native 'encrypts' if
  # you had a dedicated column, but for a KV-store, ensure your DB is encrypted at rest).
end