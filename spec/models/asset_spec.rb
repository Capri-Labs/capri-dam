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

    it 'delegates to the active version when one is present' do
      asset = create(:asset)
      version = create(:asset_version, asset: asset)
      attachment = instance_double(ActiveStorage::Attached::One)

      asset.update!(active_version: version)
      allow(version).to receive(:file).and_return(attachment)

      expect(asset.current_file).to eq(attachment)
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

  describe '#publish! / #unpublish! / #published?' do
    it 'is unpublished by default' do
      expect(create(:asset)).not_to be_published
    end

    it 'sets published_at and #published? on #publish!' do
      asset = create(:asset)
      asset.publish!
      expect(asset.reload.published_at).to be_present
      expect(asset).to be_published
    end

    it 'clears published_at on #unpublish!' do
      asset = create(:asset)
      asset.publish!
      asset.unpublish!
      expect(asset.reload.published_at).to be_nil
      expect(asset).not_to be_published
    end

    it 'cancels a pending scheduled action of either type when publishing immediately' do
      asset = create(:asset)
      user = create(:user)
      pending = asset.scheduled_publish_actions.create!(
        action_type: 'unpublish', scheduled_at: 1.hour.from_now, created_by: user
      )

      asset.publish!

      expect(pending.reload).to be_cancelled
    end
  end

  describe '.currently_published' do
    it 'only includes assets with published_at set' do
      published = create(:asset)
      published.publish!
      unpublished = create(:asset)

      expect(Asset.currently_published).to include(published)
      expect(Asset.currently_published).not_to include(unpublished)
    end
  end
end
