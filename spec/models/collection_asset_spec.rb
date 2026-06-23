require 'rails_helper'

RSpec.describe CollectionAsset, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      expect(build(:collection_asset)).to be_valid
    end

    it 'prevents the same asset appearing in a collection twice' do
      ca = create(:collection_asset)
      dup = build(:collection_asset, collection: ca.collection, asset: ca.asset)
      expect(dup).not_to be_valid
    end
  end

  describe 'position assignment' do
    it 'auto-assigns an incrementing position on create' do
      collection = create(:collection)
      a1 = create(:collection_asset, collection: collection)
      a2 = create(:collection_asset, collection: collection)
      expect(a1.position).to eq(1)
      expect(a2.position).to eq(2)
    end
  end

  describe '#manually_curated?' do
    it 'is true when no rule is linked' do
      ca = build(:collection_asset, collection_rule_id: nil)
      expect(ca.manually_curated?).to be(true)
    end
  end
end
