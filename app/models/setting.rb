class Setting < ApplicationRecord
  # Ensure settings have database-level integrity
  validates :key, presence: true, uniqueness: true

  # Serialize the text column to behave like a Hash using YAML/JSON under the hood
  serialize :value, coder: YAML

  # Encrypt the serialized Hash transparently in PostgreSQL.
  # Note: If migrating an existing database with unencrypted records, ensure
  # config.active_record.encryption.support_unencrypted_data = true is enabled
  # in Rails application configuration.
  encrypts :value, deterministic: false

  def self.set(key_name, value)
    setting = find_or_initialize_by(key: key_name.to_s)
    setting.value = value
    setting.save!
  end

  # Safe getter that fetches the raw value or configuration
  def self.get(key_name)
    data = find_by(key: key_name.to_s)&.value

    # If it's a hash wrapped inside our safety dictionary, unwrap it cleanly
    if data.is_a?(Hash) && data.keys == [:val]
      data[:val]
    else
      data
    end
  end

  # =========================================================================
  # Active Storage & Provider Integrations
  # =========================================================================

  # Fetches cloud credentials (e.g. AWS, Azure) and masks secrets
  # before sending them to the React frontend UI
  def self.get_provider_config(provider)
    raw_data = get("storage_config_#{provider}")

    data = if raw_data.is_a?(Hash)
             raw_data
           elsif raw_data.is_a?(String)
             begin
               JSON.parse(raw_data)
             rescue JSON::ParserError
               {}
             end
           else
             {}
           end

    # Mask storage secrets before sending down the wire to React
    data.transform_keys!(&:to_s) # Ensure consistent string key lookups
    data.each do |key, value|
      if key.downcase.include?('secret') && value.present?
        data[key] = "********"
      end
    end

    data
  end

  # =========================================================================
  # Outbound SMTP Engine
  # =========================================================================

  # Applies dynamic database-backed SMTP settings directly to ActionMailer on the fly.
  # Can be triggered inside a background job, initializer, or controller context.
  def self.apply_smtp_settings!
    config = get('smtp_settings')
    return if config.blank? || config['enabled'] != 'true'

    ActionMailer::Base.delivery_method = :smtp
    ActionMailer::Base.smtp_settings = {
      address:              config['address'],
      port:                 config['port'].to_i,
      domain:               config['domain'],
      user_name:            config['user_name'],
      password:             config['password'],
      authentication:       config['authentication']&.to_sym || :plain,
      enable_starttls_auto: config['enable_starttls_auto'] == 'true'
    }
  end

end