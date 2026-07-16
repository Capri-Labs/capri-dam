require 'rails_helper'

RSpec.describe Folder, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      expect(build(:folder)).to be_valid
    end

    it 'requires a name' do
      expect(build(:folder, name: nil)).not_to be_valid
    end

    it 'enforces unique names within the same parent and owner' do
      user   = create(:user)
      parent = create(:folder, user: user)
      create(:folder, name: 'Campaigns', parent: parent, user: user)
      dup = build(:folder, name: 'Campaigns', parent: parent, user: user)
      expect(dup).not_to be_valid
    end
  end

  describe 'hierarchy' do
    it 'links children to their parent' do
      parent = create(:folder)
      child  = create(:folder, parent: parent, user: parent.user)
      expect(parent.children).to include(child)
    end

    it '#path_hierarchy returns ancestors root-first' do
      user   = create(:user)
      root   = create(:folder, name: 'Root', user: user)
      sub    = create(:folder, name: 'Sub', parent: root, user: user)
      names  = sub.path_hierarchy.map { |h| h[:name] }
      expect(names).to eq(%w[Root Sub])
    end
  end

  describe 'slug generation' do
    it 'parameterizes the name into a slug' do
      folder = create(:folder, name: 'My Brand Assets')
      expect(folder.slug).to eq('my-brand-assets')
    end
  end

  describe 'soft delete' do
    it 'moves the folder out of the active scope' do
      folder = create(:folder)
      folder.soft_delete
      expect(Folder.active).not_to include(folder)
    end
  end

  # ===========================================================================
  # #self_or_ancestor_match? — cycle guard used by the Move feature
  # ===========================================================================
  describe '#self_or_ancestor_match?' do
    it 'returns true when the candidate id is the folder itself' do
      folder = create(:folder)
      expect(folder.self_or_ancestor_match?(folder.id)).to be true
    end

    it 'returns true when the candidate is a descendant of the folder' do
      user   = create(:user)
      root   = create(:folder, user: user, name: 'Root')
      child  = create(:folder, user: user, parent: root, name: 'Child')
      grandchild = create(:folder, user: user, parent: child, name: 'Grandchild')

      expect(root.self_or_ancestor_match?(grandchild.id)).to be true
    end

    it 'returns false when the candidate is an unrelated folder' do
      user  = create(:user)
      a     = create(:folder, user: user, name: 'A')
      b     = create(:folder, user: user, name: 'B')

      expect(a.self_or_ancestor_match?(b.id)).to be false
    end

    it 'returns false when the candidate is nil (root destination)' do
      folder = create(:folder)
      expect(folder.self_or_ancestor_match?(nil)).to be false
    end

    it 'returns false when the candidate is the folder\'s own parent (moving up is fine)' do
      user   = create(:user)
      parent = create(:folder, user: user, name: 'Parent')
      child  = create(:folder, user: user, parent: parent, name: 'Child')

      expect(child.self_or_ancestor_match?(parent.id)).to be false
    end
  end

  # ===========================================================================
  # .expand_ids_with_descendants — used by the Reports folder filter to
  # implicitly include sub-folders when a parent folder is selected.
  # ===========================================================================
  describe '.expand_ids_with_descendants' do
    it 'includes the folder itself plus every descendant' do
      user       = create(:user)
      root       = create(:folder, user: user, name: 'Root')
      child      = create(:folder, user: user, parent: root, name: 'Child')
      grandchild = create(:folder, user: user, parent: child, name: 'Grandchild')
      unrelated  = create(:folder, user: user, name: 'Unrelated')

      result = Folder.expand_ids_with_descendants([ root.id ])

      expect(result).to include(root.id.to_s, child.id.to_s, grandchild.id.to_s)
      expect(result).not_to include(unrelated.id.to_s)
    end

    it 'handles multiple starting ids without duplicates' do
      user  = create(:user)
      a     = create(:folder, user: user, name: 'A')
      a_kid = create(:folder, user: user, parent: a, name: 'AKid')
      b     = create(:folder, user: user, name: 'B')

      result = Folder.expand_ids_with_descendants([ a.id, b.id, a.id ])

      expect(result.tally.values).to all(eq(1))
      expect(result).to match_array([ a.id.to_s, a_kid.id.to_s, b.id.to_s ])
    end

    it 'returns an empty array for blank input' do
      expect(Folder.expand_ids_with_descendants(nil)).to eq([])
      expect(Folder.expand_ids_with_descendants([])).to eq([])
    end

    it 'ignores soft-deleted descendant folders' do
      user    = create(:user)
      root    = create(:folder, user: user, name: 'Root2')
      trashed = create(:folder, user: user, parent: root, name: 'Trashed', deleted_at: Time.current)

      result = Folder.expand_ids_with_descendants([ root.id ])

      expect(result).not_to include(trashed.id.to_s)
    end
  end
end
