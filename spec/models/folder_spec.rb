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
end
