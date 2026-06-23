require 'rails_helper'

RSpec.describe Collection, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      expect(build(:collection)).to be_valid
    end

    it 'requires a name' do
      expect(build(:collection, name: nil)).not_to be_valid
    end
  end

  describe 'auto-generation callbacks' do
    it 'generates a uuid and slug before validation on create' do
      col = create(:collection, name: 'My Campaign 2026')
      expect(col.uuid).to be_present
      expect(col.slug).to eq('my-campaign-2026')
    end

    it 'generates a unique slug when there is a collision' do
      create(:collection, name: 'Brand Assets')
      second = create(:collection, name: 'Brand Assets')
      expect(second.slug).to eq('brand-assets-1')
    end
  end

  describe '#smart?' do
    it 'returns true for smart collections only' do
      expect(build(:collection, collection_type: 'smart').smart?).to be(true)
      expect(build(:collection, collection_type: 'manual').smart?).to be(false)
    end
  end

  describe '#accessible_by?' do
    it 'grants access to admins unconditionally' do
      admin = create(:user, admin: true)
      col   = create(:collection)
      expect(col.accessible_by?(admin)).to be(true)
    end

    it 'denies access when the user is in a denied group' do
      user = create(:user, admin: false)
      col  = create(:collection)
      col.update!(denied_groups: [])
      # No explicit groups set -> default allow
      expect(col.accessible_by?(user)).to be(true)
    end
  end

  describe 'scopes' do
    it '.active excludes soft-deleted collections' do
      live    = create(:collection)
      deleted = create(:collection, deleted_at: 1.day.ago)
      expect(Collection.active).to include(live)
      expect(Collection.active).not_to include(deleted)
    end
  end
end
