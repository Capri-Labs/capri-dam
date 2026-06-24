# Authenticated user of the Headless DAM platform.
#
# Users are authenticated via Devise with two identity providers:
# * **Local** — email + password managed inside the DAM database.
# * **SSO (Keycloak OpenID)** — federated via OmniAuth; passwords are
#   random tokens the user never needs to know.
#
# == Authorization model
#
# Permissions are **group-based** using a closure-table hierarchy:
#
# 1. Each user belongs to one or more {UserGroup}s.
# 2. Groups are arranged in a tree; membership in a child group implies
#    membership in all its ancestors (computed via {UserGroupClosure}).
# 3. {FolderPolicy} records attach permission bits to (group, folder) pairs.
# 4. {#permissions_for} aggregates those bits using an optimistic OR strategy.
#    A single +explicit_deny+ on any inherited group short-circuits all access.
#
# == Soft deletion
#
# Users are never hard-deleted.  {#deactivate!} stamps +active: false+ which
# Devise's {#active_for_authentication?} hook enforces at login time.
#
# @see FolderPolicy
# @see UserGroup
# @see UserGroupClosure
class User < ApplicationRecord
  include Auditable

  # ---------------------------------------------------------------------------
  # Devise modules
  # ---------------------------------------------------------------------------

  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :omniauthable, omniauth_providers: %i[keycloak_openid]

  # ---------------------------------------------------------------------------
  # Associations
  # ---------------------------------------------------------------------------

  has_many :folders,               dependent: :destroy
  has_many :assets,                dependent: :destroy
  has_many :user_group_memberships, dependent: :destroy
  has_many :user_groups,           through: :user_group_memberships
  has_many :notifications,         dependent: :destroy
  has_many :metadata_exports,      dependent: :destroy
  has_many :metadata_imports,      dependent: :destroy

  # ---------------------------------------------------------------------------
  # Validations
  # ---------------------------------------------------------------------------

  # Email is the canonical identity; it must be unique (case-insensitive).
  validates :email, presence: true, uniqueness: { case_sensitive: false }

  # ---------------------------------------------------------------------------
  # Class methods
  # ---------------------------------------------------------------------------

  # Finds or creates a user from an OmniAuth authentication hash.
  #
  # New users are provisioned with a random password (they never need to use
  # it) and a username derived from the email local-part suffixed with +"_sso"+.
  #
  # @param auth [OmniAuth::AuthHash] the hash returned by the provider callback
  # @return [User] the persisted (possibly newly created) user record
  def self.from_omniauth(auth)
    where(provider: auth.provider, uid: auth.uid).first_or_create do |user|
      user.email    = auth.info.email
      user.password = Devise.friendly_token[0, 20]
      user.name     = auth.info.name
      generated_username = auth.info.email.split('@').first
      user.username = "#{generated_username}_sso"
    end
  end

  # ---------------------------------------------------------------------------
  # Instance methods — identity
  # ---------------------------------------------------------------------------

  # Returns the user's full name, falling back to email when names are absent.
  #
  # @return [String]
  def full_name
    "#{first_name} #{last_name}".strip.presence || email
  end

  # Human-readable display name suitable for UI labels.
  # Prefers +name+, then +"first last"+, then the email local-part.
  #
  # @return [String]
  def display_name
    name.presence ||
      [first_name, last_name].compact.join(' ').presence ||
      email.split('@').first
  end

  # Returns +true+ when this user's identity is managed by an external SSO provider.
  #
  # @return [Boolean]
  def sso_managed?
    provider.present? && uid.present?
  end

  # Returns +true+ when this user authenticates with a local DAM password.
  #
  # @return [Boolean]
  def local_managed?
    !sso_managed?
  end

  # ---------------------------------------------------------------------------
  # Instance methods — authorisation
  # ---------------------------------------------------------------------------

  # Returns the flat set of group IDs that this user inherits permissions from,
  # including all ancestor groups in the closure tree.
  #
  # This executes a **single** database query with no application-level recursion.
  #
  # @return [ActiveRecord::Relation<Integer>] ancestor group IDs
  def effective_group_ids
    direct_ids = user_groups.select(:id)
    UserGroupClosure.where(descendant_id: direct_ids).select(:ancestor_id)
  end

  # Computes the effective permission set for the user inside a specific folder.
  #
  # The algorithm is:
  # 1. Super-admins always receive full access.
  # 2. If any inherited group has +explicit_deny+, all permissions are denied.
  # 3. Otherwise permissions are aggregated with an optimistic OR across all
  #    applicable {FolderPolicy} records.
  #
  # @param folder [Folder] the folder to evaluate permissions against
  # @return [Hash{Symbol => Boolean}] keys: +:read+, +:write+, +:delete+,
  #   +:manage+, +:approve+
  def permissions_for(folder)
    return { read: true, write: true, delete: true, manage: true, approve: true } if admin?

    policies = FolderPolicy.where(folder_id: folder.id, user_group_id: effective_group_ids)

    if policies.any?(&:explicit_deny)
      return { read: false, write: false, delete: false, manage: false, approve: false }
    end

    {
      read:    policies.any?(&:read_access),
      write:   policies.any?(&:write_access),
      delete:  policies.any?(&:delete_access),
      manage:  policies.any?(&:manage_access),
      approve: policies.any?(&:approval_flow)
    }
  end

  # Returns +true+ when the user has read access to the given folder.
  #
  # @param folder [Folder]
  # @return [Boolean]
  def can_see_folder?(folder)
    permissions_for(folder)[:read]
  end

  # Role predicate — returns +true+ when the user holds the given role OR is an admin.
  #
  # Admins are treated as possessing every role, so callers never need to
  # special-case them separately.
  #
  # @example
  #   user.role?(:manager)   # => true when role == "manager" OR admin?
  # @param required_role [String, Symbol] the role to test
  # @return [Boolean]
  def role?(required_role)
    admin? || role.to_s == required_role.to_s
  end

  # ---------------------------------------------------------------------------
  # Instance methods — lifecycle
  # ---------------------------------------------------------------------------

  # Deactivates the account, blocking future logins.
  #
  # @return [Boolean]
  def deactivate!
    update(active: false)
  end

  # Re-activates a previously deactivated account.
  #
  # @return [Boolean]
  def reactivate!
    update(active: true)
  end

  # Devise hook — prevents login when +active+ is +false+.
  #
  # @return [Boolean]
  def active_for_authentication?
    super && active?
  end

  # Devise hook — returns the flash message key used when login is blocked.
  #
  # @return [Symbol]
  def inactive_message
    active? ? super : :account_deactivated
  end
end