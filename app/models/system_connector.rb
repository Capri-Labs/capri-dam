class SystemConnector < ApplicationRecord
  before_create :generate_webhook_secret

  private

  def generate_webhook_secret
    # Generates a 64-character secure hexadecimal string
    self.webhook_secret = SecureRandom.hex(32)
  end
end