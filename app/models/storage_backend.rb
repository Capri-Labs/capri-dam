class StorageBackend < ApplicationRecord
  PROVIDER_TYPES = StorageManager::ADAPTERS.keys.freeze

  validates :name, presence: true
  validates :provider_type, presence: true, inclusion: { in: PROVIDER_TYPES }
  validates :configuration, presence: true

  # Only one backend can be active at a time (enforced by SettingsController#sync_to_storage_backend!)
  scope :active_backend, -> { find_by(active: true) }

  # Instantiate the correct adapter for this backend
  def adapter
    StorageManager.adapter_for(self)
  end

  # Verify connectivity without modifying any state
  def test_connection
    adapter.test_connection
  rescue => e
    { success: false, error: e.message }
  end

  # Mask secret values before serializing (e.g. for API responses)
  def masked_configuration
    configuration.each_with_object({}) do |(k, v), h|
      h[k] = k.to_s.match?(/secret|key|password|token|credentials/i) && v.present? ? '********' : v
    end
  end
end
