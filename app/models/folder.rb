# Hierarchical folder model that organises {Asset}s inside the DAM.
#
# Folders form an **n-ary tree** via the self-referential +parent_id+ / +children+
# association.  They also carry ABAC access-control data through associated
# {FolderPolicy} records that attach permission bits to {UserGroup}s.
#
# == Naming & slugging
#
# * +name+ must be unique within the same parent folder and user.
# * A URL-safe +slug+ is auto-generated from +name+ on create/rename.
# * A stable +uuid+ is generated on create and used as the external identifier.
#
# == Soft deletion
#
# Folders inherit {SoftDeletable}; deleting a folder stamps +deleted_at+ rather
# than cascading a hard-delete.  Child folders and assets are soft-deleted
# separately by the controller.
#
# @see Asset
# @see FolderPolicy
# @see SoftDeletable
class Folder < ApplicationRecord
  # ---------------------------------------------------------------------------
  # Associations
  # ---------------------------------------------------------------------------

  # @!attribute [r] user
  #   @return [User] the user who created / owns this folder
  belongs_to :user

  # @!attribute [r] parent
  #   @return [Folder, nil] direct parent in the hierarchy; +nil+ for root folders
  belongs_to :parent, class_name: "Folder", optional: true

  # @!attribute [r] children
  #   @return [ActiveRecord::Associations::CollectionProxy<Folder>]
  #     immediate child folders; cascade-destroyed when parent is destroyed
  has_many :children, class_name: "Folder", foreign_key: "parent_id", dependent: :destroy

  # @!attribute [r] assets
  #   @return [ActiveRecord::Associations::CollectionProxy<Asset>]
  has_many :assets, dependent: :destroy

  # @!attribute [r] folder_policies
  #   @return [ActiveRecord::Associations::CollectionProxy<FolderPolicy>]
  has_many :folder_policies, dependent: :destroy

  # ---------------------------------------------------------------------------
  # Validations
  # ---------------------------------------------------------------------------

  validates :name, presence: true
  validates :user_id, presence: true
  validates :name,
            uniqueness: { scope: [ :parent_id, :user_id ],
                          message: "already exists in this location" }

  # ---------------------------------------------------------------------------
  # Callbacks
  # ---------------------------------------------------------------------------

  before_validation :ensure_uuid, on: :create
  before_validation :generate_slug, if: -> { name.present? && (name_changed? || slug.blank?) }

  include SoftDeletable

  # ---------------------------------------------------------------------------
  # Instance methods
  # ---------------------------------------------------------------------------

  # Walks up the ancestor chain and returns the full breadcrumb path as an
  # ordered array of hashes.  Useful for the React breadcrumb component.
  #
  # @example
  #   folder.path_hierarchy
  #   # => [{ id: 1, name: "Root", slug: "root" },
  #   #     { id: 5, name: "Marketing", slug: "marketing" },
  #   #     { id: 9, name: "EMEA", slug: "emea" }]
  #
  # @return [Array<Hash>] ordered from root to self, each entry containing
  #   +:id+, +:name+, and +:slug+
  def path_hierarchy
    path    = []
    current = self
    while current
      path.unshift({ id: current.id, name: current.name, slug: current.slug })
      current = current.parent
    end
    path
  end

  # Returns the {UserGroup}s that have at least one {FolderPolicy} governing
  # this specific folder.
  #
  # @return [ActiveRecord::Relation<UserGroup>]
  def governing_groups
    UserGroup.joins(:folder_policies).where(folder_policies: { folder_id: id })
  end

  # Walks up the ancestor chain from +candidate_id+ looking for +self+.
  # Used by the Move feature to reject drops that would create a cycle
  # (moving a folder into itself or into one of its own descendants).
  #
  # @param candidate_id [Integer, String, nil] the prospective destination
  #   folder id (+nil+ means "root", which is never a descendant of self)
  # @return [Boolean] true when +candidate_id+ is +self+ or a descendant of
  #   +self+
  def self_or_ancestor_match?(candidate_id)
    return false if candidate_id.blank?

    current = Folder.find_by(id: candidate_id)
    while current
      return true if current.id == id
      current = current.parent
    end
    false
  end

  # Expands a list of folder ids to include every descendant folder id
  # (recursive), so filters like "assets in these folders" naturally include
  # sub-folders. Computed with a single in-memory pass over all active
  # folders' (id, parent_id) pairs rather than a recursive SQL CTE — the
  # folder tree is small enough that this is simpler and just as fast.
  #
  # @param ids [Array<String, Integer>] one or more starting folder ids
  # @return [Array<String>] +ids+ plus every descendant id, as strings
  def self.expand_ids_with_descendants(ids)
    ids = Array(ids).compact.map(&:to_s)
    return [] if ids.empty?

    children_by_parent = Folder.active.pluck(:id, :parent_id)
                                .group_by { |(_id, parent_id)| parent_id.to_s }

    result = Set.new(ids)
    queue = ids.dup
    until queue.empty?
      current_id = queue.shift
      (children_by_parent[current_id] || []).each do |(child_id, _parent_id)|
        child_id = child_id.to_s
        next if result.include?(child_id)

        result << child_id
        queue << child_id
      end
    end
    result.to_a
  end

  private

  # Generates a URL-safe slug from +name+ using Rails' +parameterize+.
  # @api private
  def generate_slug
    self.slug = name.parameterize
  end

  # Ensures a UUID is present before validation on create.
  # @api private
  def ensure_uuid
    self.uuid ||= SecureRandom.uuid
  end
end
