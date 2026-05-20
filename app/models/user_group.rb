class UserGroup < ApplicationRecord
  validates :name, presence: true, uniqueness: true

  has_many :user_group_memberships, dependent: :destroy
  has_many :users, through: :user_group_memberships
  has_many :folder_policies, dependent: :destroy

  # Self-referential initialization for the Closure Table
  after_create :initialize_closure_self

  # Link to the closure table mappings
  has_many :ancestor_closures, class_name: 'UserGroupClosure', foreign_key: 'descendant_id', dependent: :delete_all
  has_many :descendant_closures, class_name: 'UserGroupClosure', foreign_key: 'ancestor_id', dependent: :delete_all

  has_many :ancestors, through: :ancestor_closures, source: :ancestor
  has_many :descendants, through: :descendant_closures, source: :descendant

  # Establishes a parent-child relationship and recalculates the structural paths
  def add_child(child_group)
    return if child_group.id == self.id # Prevent infinite loops

    ActiveRecord::Base.transaction do
      # For every ancestor of the PARENT (including the parent itself),
      # map a new path to the CHILD
      self.ancestor_closures.each do |closure|
        UserGroupClosure.find_or_create_by!(
          ancestor_id: closure.ancestor_id,
          descendant_id: child_group.id,
          distance: closure.distance + 1
        )
      end
    end
  end

  private

  def initialize_closure_self
    # Every group is technically its own ancestor at a distance of 0.
    # This makes our SQL JOINs incredibly efficient later.
    UserGroupClosure.create!(ancestor_id: id, descendant_id: id, distance: 0)
  end
end