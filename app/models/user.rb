class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :omniauthable, omniauth_providers: %i[keycloak_openid]

  validates :username, presence: true, uniqueness: true

  def self.from_omniauth(auth)
    # 1. Try to find the user by provider/uid
    # 2. If not found, create them
    where(provider: auth.provider, uid: auth.uid).first_or_create do |user|
      user.email = auth.info.email
      user.password = Devise.friendly_token[0, 20]
      user.name = auth.info.name

      # Since your model validates username, we generate one from the email
      # e.g., "ashok.pelluru@enterprise.com" -> "ashok.pelluru_sso"
      generated_username = auth.info.email.split('@').first
      user.username = "#{generated_username}_sso"
    end
  end

  has_many :folders, dependent: :destroy
  has_many :assets, dependent: :destroy
end