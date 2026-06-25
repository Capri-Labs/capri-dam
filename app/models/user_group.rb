# Hierarchical group of users used for permission allocation.
#
# == Built-in (system) groups
#
# Three groups are seeded automatically and are **immutable**:
#
# | Slug                    | Purpose |
# |-------------------------|---------|
# | +everyone+              | Every user is implicitly a member.  Cannot be deleted or modified. |
# | +administrators+        | Full access to all assets/folders.  Only a super-admin can edit membership. |
# | +super-administrators+  | Reserved for strictest system operations.  Cannot be deleted. |
#
# @see UserGroupClosure
# @see FolderPolicy
# @see User
class UserGroup < ApplicationRecord
  # ---------------------------------------------------------------------------
  # Built-in group slugs
  # ---------------------------------------------------------------------------

  SYSTEM_SLUGS = %w[everyone administrators super-administrators].freeze

  # ---------------------------------------------------------------------------
  # Guards
  # ---------------------------------------------------------------------------

  before_destroy :prevent_system_group_deletion
  validate       :enforce_system_group_immutability, on: :update

  # ---------------------------------------------------------------------------
  # Validations
  # ---------------------------------------------------------------------------

  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :slug, uniqueness: { case_sensitive: false }, allow_blank: true

  # ---------------------------------------------------------------------------
  # Associations
  # ---------------------------------------------------------------------------

  belongs_to :parent, class_name: 'UserGroup', optional: true

  has_many :user_group_memberships, dependent: :destroy
  has_many :users, through: :user_group_memberships
  has_many :folder_policies, dependent: :destroy
  has_many :child_groups, class_name: 'UserGroup', foreign_key: :parent_id, dependent: :nullify

  has_many :ancestor_closures,   class_name: 'UserGroupClosure', foreign_key: 'descendant_id', dependent: :delete_all
  has_many :descendant_closures, class_name: 'UserGroupClosure', foreign_key: 'ancestor_id',   dependent: :delete_all

  has_many :ancestors,   through: :ancestor_closures,   source: :ancestor
  has_many :descendants, through: :descendant_closures, source: :descendant

  # ---------------------------------------------------------------------------
  # Callbacks
  # ---------------------------------------------------------------------------

  after_create :initialize_closure_self

  # ---------------------------------------------------------------------------
  # Scopes
  # ---------------------------------------------------------------------------

  scope :system,     -> { where(is_system: true) }
  scope :non_system, -> { where(is_system: false) }

  # ---------------------------------------------------------------------------
  # Class helpers
  # ---------------------------------------------------------------------------

  def self.everyone          = find_by!(slug: 'everyone')
  def self.administrators    = find_by!(slug: 'administrators')
  def self.super_administrators = find_by!(slug: 'super-administrators')

  # ---------------------------------------------------------------------------
  # Instance helpers
  # ---------------------------------------------------------------------------

  def system?          = is_system? || SYSTEM_SLUGS.include?(slug.to_s)
  def everyone?        = slug == 'everyone'
  def administrators?  = slug == 'administrators'
  def super_administrators? = slug == 'super-administrators'
  def member_count     = users.count

  # Establishes a parent-child relationship and updates all closure paths.
  def add_child(child_group)
    return if child_group.id == id

    ActiveRecord::Base.transaction do
      ancestor_closures.each do |closure|
        UserGroupClosure.find_or_create_by!(
          ancestor_id:   closure.ancestor_id,
          descendant_id: child_group.id,
          distance:      closure.distance + 1
        )
      end
    end
  end

  # Returns all users belonging to this group or any descendant group.
  def all_members
    descendant_ids = UserGroupClosure.where(ancestor_id: id).select(:descendant_id)
    User.joins(:user_group_memberships)
        .where(user_group_memberships: { user_group_id: descendant_ids })
        .distinct
  end

  private

  def initialize_closure_self
    UserGroupClosure.create!(ancestor_id: id, descendant_id: id, distance: 0)
  end

  def prevent_system_group_deletion
    if system?
      errors.add(:base, "System group '#{name}' cannot be deleted.")
      throw :abort
    end
  end

  def enforce_system_group_immutability
    return unless persisted?

    if slug_changed? && is_system_was
      errors.add(:slug, "cannot be changed for a system group.")
    end
    if is_system_changed? && !is_system? && is_system_was
      errors.add(:is_system, "cannot be removed from a system group.")
    end
  end
end