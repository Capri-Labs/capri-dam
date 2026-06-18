class CdnConfiguration < ApplicationRecord
  validates :provider, presence: true, uniqueness: true

  # 🚀 SECURITY BY DESIGN: Encrypts the entire JSON payload at rest.
  # The database only sees ciphertext. Rails decrypts it in memory.
  encrypts :settings, type: :json

  # Ensure only one CDN is active at a time
  before_save :ensure_single_active_provider

  private

  def ensure_single_active_provider
    if self.is_active?
      CdnConfiguration.where.not(id: self.id).update_all(is_active: false)
    end
  end
end