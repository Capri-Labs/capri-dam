class CdnConfiguration < ApplicationRecord
  validates :provider, presence: true, uniqueness: true

  # 🚀 SECURITY BY DESIGN: Encrypts the entire JSON payload at rest.
  # The database only sees ciphertext. Rails decrypts it in memory.
  #
  # NOTE: `encrypts ..., type: :json` is NOT a valid option on this Rails
  # version (it silently corrupts the encryption context — see
  # ActiveRecord::Encryption::EncryptableRecord#encrypts, and the same fix
  # already applied in SystemConnector). The correct way to get JSON
  # semantics on an encrypted column is to declare the attribute's cast type
  # first, then encrypt it with no extra options.
  attribute :settings, :json
  encrypts :settings

  # Ensure only one CDN is active at a time
  before_save :ensure_single_active_provider

  private

  def ensure_single_active_provider
    if self.is_active?
      CdnConfiguration.where.not(id: self.id).update_all(is_active: false)
    end
  end
end
