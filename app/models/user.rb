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
# == Everyone group
#
# Every user is automatically added to the built-in "everyone" group on
# creation (and after SSO sync).  This provides a baseline for default
# folder access rights without requiring explicit group assignments.
#
# == Impersonation
#
# An admin can grant another user the ability to impersonate this account.
# {#can_be_impersonated_by?} tests that grant, and {#impersonating_accounts}
# lists accounts this user is allowed to act as.
#
# == Keycloak SSO sync
#
# {.from_omniauth} provisions new SSO users and syncs mutable profile
# fields (name, first/last name, avatar_url) from the Keycloak token on
# every subsequent login.  The email and uid are never changed after initial
# provisioning to preserve referential integrity.
#
# == Soft deletion
#
# Users are never hard-deleted.  {#deactivate!} stamps +active: false+ which
# Devise's {#active_for_authentication?} hook enforces at login time.
#
# @see FolderPolicy
# @see UserGroup
# @see UserGroupClosure
# @see UserImpersonator
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

  has_many :folders,                dependent: :destroy
  has_many :assets,                 dependent: :destroy
  has_many :user_group_memberships, dependent: :destroy
  has_many :user_groups,            through: :user_group_memberships
  has_many :notifications,          dependent: :destroy
  has_many :metadata_exports,       dependent: :destroy
  has_many :metadata_imports,       dependent: :destroy
  has_one  :preference, class_name: 'UserPreference', dependent: :destroy

  # Impersonation: accounts that may impersonate THIS user
  has_many :impersonator_grants, class_name: 'UserImpersonator',
           foreign_key: :user_id, dependent: :destroy
  has_many :impersonators, through: :impersonator_grants,
           source: :impersonator

  # Impersonation: accounts THIS user is allowed to act as
  has_many :impersonatee_grants, class_name: 'UserImpersonator',
           foreign_key: :impersonator_id, dependent: :destroy
  has_many :impersonating_accounts, through: :impersonatee_grants,
           source: :user

  # ---------------------------------------------------------------------------
  # Validations
  # ---------------------------------------------------------------------------

  validates :email, presence: true, uniqueness: { case_sensitive: false }

  # ---------------------------------------------------------------------------
  # Callbacks
  # ---------------------------------------------------------------------------

  after_create :add_to_everyone_group
  after_create :create_default_preference

  # ---------------------------------------------------------------------------
  # Class methods
  # ---------------------------------------------------------------------------

  # Finds or creates a user from an OmniAuth authentication hash, syncing
  # profile fields from Keycloak on every login.
  #
  # New SSO users receive a random password (they will never type it) and a
  # username derived from the email local-part suffixed with +"_sso"+.
  #
  # @param auth [OmniAuth::AuthHash]
  # @return [User]
  def self.from_omniauth(auth)
    user = where(provider: auth.provider, uid: auth.uid).first_or_initialize

    if user.new_record?
      user.email    = auth.info.email
      user.password = Devise.friendly_token[0, 20]
      user.name     = auth.info.name.presence || auth.info.email.split('@').first
      user.username = "#{auth.info.email.split('@').first}_sso"
    else
      # Sync mutable fields on every login
      user.name       = auth.info.name.presence || user.name
      user.first_name = auth.info.first_name.presence || user.first_name
      user.last_name  = auth.info.last_name.presence  || user.last_name
      user.avatar_url = auth.info.image.presence      || user.avatar_url
    end

    user.save!
    user
  end

  # ---------------------------------------------------------------------------
  # Instance methods — identity
  # ---------------------------------------------------------------------------

  # @return [String]
  def full_name
    "#{first_name} #{last_name}".strip.presence || email
  end

  # Prefers +name+, then +"first last"+, then the email local-part.
  # @return [String]
  def display_name
    name.presence ||
      [first_name, last_name].compact.join(' ').presence ||
      email.split('@').first
  end

  # @return [Boolean]
  def sso_managed?
    provider.present? && uid.present?
  end

  # @return [Boolean]
  def local_managed?
    !sso_managed?
  end

  # ---------------------------------------------------------------------------
  # Instance methods — authorisation
  # ---------------------------------------------------------------------------

  # Returns the flat set of group IDs this user inherits permissions from,
  # including all ancestor groups via the closure table.
  #
  # @return [ActiveRecord::Relation<Integer>]
  def effective_group_ids
    direct_ids = user_groups.select(:id)
    UserGroupClosure.where(descendant_id: direct_ids).select(:ancestor_id)
  end

  # Returns +true+ when this user is a member of the administrators or
  # super-administrators built-in groups.
  # @return [Boolean]
  def super_admin?
    user_groups.where(slug: 'super-administrators').exists?
  end

  # Computes the effective permission set for the user inside a specific folder.
  #
  # Algorithm:
  # 1. Admins / super-admins always receive full access (bypasses deny-all).
  # 2. +explicit_deny+ on ANY inherited group short-circuits all access.
  # 3. Otherwise permissions are OR-aggregated across all applicable policies.
  #
  # @param folder [Folder]
  # @return [Hash{Symbol => Boolean}] +:read+, +:modify+, +:create+, +:delete+, +:replicate+, +:manage+
  def permissions_for(folder)
    if admin? || super_admin? || member_of_administrators?
      return full_permissions
    end

    policies = FolderPolicy.where(folder_id: folder.id, user_group_id: effective_group_ids)

    if policies.any?(&:explicit_deny)
      return denied_permissions
    end

    {
      read:      policies.any?(&:read_access),
      modify:    policies.any?(&:modify_access),
      create:    policies.any?(&:create_access),
      delete:    policies.any?(&:delete_access),
      replicate: policies.any?(&:replicate_access),
      manage:    policies.any?(&:manage_access)
    }
  end

  # @param folder [Folder]
  # @return [Boolean]
  def can_see_folder?(folder)
    permissions_for(folder)[:read]
  end

  # @param required_role [String, Symbol]
  # @return [Boolean]
  def role?(required_role)
    admin? || role.to_s == required_role.to_s
  end

  # Returns +true+ when this user belongs to the built-in administrators group.
  # @return [Boolean]
  def member_of_administrators?
    user_groups.where(slug: %w[administrators super-administrators]).exists?
  end

  # ---------------------------------------------------------------------------
  # Instance methods — impersonation
  # ---------------------------------------------------------------------------

  # Returns +true+ when +actor+ is authorised to impersonate this user.
  #
  # @param actor [User] the would-be impersonator
  # @return [Boolean]
  def can_be_impersonated_by?(actor)
    impersonator_grants.where(impersonator_id: actor.id).exists?
  end

  # Grants +actor+ permission to impersonate this user.
  #
  # @param actor [User]
  # @return [UserImpersonator]
  def grant_impersonation_to(actor)
    impersonator_grants.find_or_create_by!(impersonator: actor)
  end

  # Revokes impersonation permission for +actor+.
  #
  # @param actor [User]
  # @return [void]
  def revoke_impersonation_from(actor)
    impersonator_grants.where(impersonator: actor).destroy_all
  end

  # ---------------------------------------------------------------------------
  # Instance methods — lifecycle
  # ---------------------------------------------------------------------------

  # @return [Boolean]
  def deactivate!
    update(active: false)
  end

  # @return [Boolean]
  def reactivate!
    update(active: true)
  end

  # Devise hook — prevents login when +active+ is +false+.
  # @return [Boolean]
  def active_for_authentication?
    super && active?
  end

  # @return [Symbol]
  def inactive_message
    active? ? super : :account_deactivated
  end

  # Returns or creates this user's preference record.
  # @return [UserPreference]
  def preference!
    preference || create_preference
  end

  private

  # ---------------------------------------------------------------------------

  def add_to_everyone_group
    everyone = UserGroup.find_by(slug: 'everyone')
    user_groups << everyone if everyone && !user_groups.include?(everyone)
  rescue StandardError => e
    Rails.logger.warn("[User] Could not add #{email} to everyone group: #{e.message}")
  end

  def create_default_preference
    create_preference unless preference
  rescue StandardError => e
    Rails.logger.warn("[User] Could not create preference for #{email}: #{e.message}")
  end

  def full_permissions
    { read: true, modify: true, create: true, delete: true, replicate: true, manage: true }
  end

  def denied_permissions
    { read: false, modify: false, create: false, delete: false, replicate: false, manage: false }
  end
end