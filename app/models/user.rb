class User < ApplicationRecord
  include Auditable

  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :omniauthable, omniauth_providers: %i[keycloak_openid]

  #validates :username, presence: true, uniqueness: true
  validates :email, presence: true, uniqueness: { case_sensitive: false }

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

  def full_name
    # Returns email if names are missing
    "#{first_name} #{last_name}".strip.presence || email
  end

  # 1. Calculates the flattened list of groups this user inherits power from
  def effective_group_ids
    # Get the IDs of the groups the user explicitly belongs to
    direct_ids = user_groups.select(:id)

    # Use the Closure table to find ALL ancestors (Parents, Grandparents)
    # of those explicit groups. This is a single, zero-recursion database query!
    UserGroupClosure.where(descendant_id: direct_ids).select(:ancestor_id)
  end

  # Determines what the user can do within a specific folder
  def permissions_for(folder)
    # Super Admins bypass all checks completely
    return { read: true, write: true, delete: true, manage: true, approve: true } if admin?

    # Fetch all policies applied to this folder for ANY of the user's effective groups
    policies = FolderPolicy.where(folder_id: folder.id, user_group_id: effective_group_ids)

    # EXPLICIT DENY OVERRIDE (The Short-Circuit)
    # If even one inherited group has explicit_deny set to true for this folder,
    # nuke all permissions immediately.
    if policies.any?(&:explicit_deny)
      return { read: false, write: false, delete: false, manage: false, approve: false }
    end

    # Aggregate the permissions using an optimistic OR strategy
    {
      read:    policies.any?(&:read_access),
      write:   policies.any?(&:write_access),
      delete:  policies.any?(&:delete_access),
      manage:  policies.any?(&:manage_access),
      approve: policies.any?(&:approval_flow)
    }
  end

  # Security Guard Clause (The Ghost Principle)
  def can_see_folder?(folder)
    permissions_for(folder)[:read]
  end

  # Identity Helpers
  def sso_managed?
    provider.present? && uid.present?
  end

  def local_managed?
    !sso_managed?
  end

  # Soft Deletion Engine (using your existing `active` boolean)
  def deactivate!
    update(active: false)
  end

  def reactivate!
    update(active: true)
  end

  # Devise hook: Blocks login if active == false
  def active_for_authentication?
    super && active?
  end

  def inactive_message
    active? ? super : :account_deactivated
  end

  def display_name
    name.presence || [first_name, last_name].compact.join(' ').presence || email.split('@').first
  end

  has_many :folders, dependent: :destroy
  has_many :assets, dependent: :destroy
  has_many :user_group_memberships, dependent: :destroy
  has_many :user_groups, through: :user_group_memberships
  has_many :notifications, dependent: :destroy
end