require 'rails_helper'

RSpec.describe Asset, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      expect(build(:asset)).to be_valid
    end

    it 'requires a title' do
      expect(build(:asset, title: nil)).not_to be_valid
    end
  end

  describe 'associations' do
    it 'belongs to a user' do
      expect(create(:asset).user).to be_present
    end

    it 'belongs to an optional folder' do
      expect(build(:asset, folder: nil)).to be_valid
    end
  end

  describe 'status enum' do
    it 'defaults to draft when not provided' do
      asset = Asset.new(title: 'X', user: create(:user))
      expect(asset.status).to eq('draft')
    end

    it 'exposes the documented states' do
      expect(Asset.statuses.keys).to include('draft', 'ready', 'approved', 'failed')
    end
  end

  describe 'property defaults' do
    it 'seeds default properties when none are supplied' do
      asset = Asset.new(properties: nil)
      expect(asset.properties).to include('usage_terms' => 'Internal Use Only')
    end
  end

  describe 'soft delete' do
    it 'is excluded from the active scope once soft-deleted' do
      asset = create(:asset)
      asset.soft_delete
      expect(Asset.active).not_to include(asset)
      expect(Asset.trashed).to include(asset)
    end

    it 'can be restored' do
      asset = create(:asset, :trashed)
      asset.restore
      expect(asset.reload.deleted_at).to be_nil
    end
  end

  describe '#broadcast_for_embedding resilience' do
    it 'does not raise when Redis is unavailable' do
      allow(Redis).to receive(:new).and_raise(StandardError.new('connection refused'))
      expect { create(:asset) }.not_to raise_error
    end
  end

  describe '#next_version_number' do
    it 'starts at 1 when there are no versions' do
      expect(create(:asset).next_version_number).to eq(1)
    end
  end

  describe '#current_file' do
    it 'returns the file attached to the active version' do
      asset = create(:asset)
      expect(asset.current_file).to eq(asset.active_version&.file)
    end
  end

  describe '.nearest_to_vector' do
    it 'returns none when the vector is blank' do
      expect(Asset.nearest_to_vector(nil)).to eq(Asset.none)
      expect(Asset.nearest_to_vector([])).to eq(Asset.none)
    end

    it 'finds assets ordered by cosine similarity to the given embedding' do
      asset = create(:asset)
      embedding = Array.new(1536, 0.001)
      asset.create_asset_embedding!(embedding: embedding, model_name: "text-embedding-3-small")

      expect(Asset.nearest_to_vector(embedding)).to include(asset)
    end
  end
end
