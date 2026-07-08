require 'rails_helper'

RSpec.describe Collection, type: :model do
  include ActiveSupport::Testing::TimeHelpers

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
      group = create(:user_group, name: 'Blocked')
      user = create(:user, admin: false)
      user.user_groups << group
      col = create(:collection, denied_groups: [ group.name ])

      expect(col.accessible_by?(user)).to be(false)
    end

    it 'requires membership in at least one allowed group when allow-lists are configured' do
      allowed = create(:user_group, name: 'Approved')
      user = create(:user, admin: false)
      outsider = create(:user, admin: false)
      user.user_groups << allowed
      col = create(:collection, allowed_groups: [ allowed.name ])

      expect(col.accessible_by?(user)).to be(true)
      expect(col.accessible_by?(outsider)).to be(false)
    end
  end

  describe '#compliance_violations' do
    it 'flags internal-use assets only when the collection is externally accessible' do
      external = create(:collection, allowed_groups: [ 'External Agencies' ])
      internal = create(:collection, allowed_groups: [ 'Employees' ])
      asset = create(:asset, properties: { 'usage_terms' => 'Internal Use Only' })
      other_asset = create(:asset, properties: { 'usage_terms' => 'Internal Use Only' })
      create(:collection_asset, collection: external, asset: asset)
      create(:collection_asset, collection: internal, asset: other_asset)

      expect(external.compliance_violations.map { |violation| violation[:reason] })
        .to include("Asset is restricted to 'Internal Use Only' but workspace allows external access.")
      expect(internal.compliance_violations).to be_empty
    end

    it 'flags assets whose license expires before the collection expires' do
      collection = create(:collection, expires_at: 10.days.from_now)
      expiring = create(:asset, properties: { 'usage_terms' => 'Licensed', 'license_expires_at' => 2.days.from_now.iso8601 })
      safe = create(:asset, properties: { 'usage_terms' => 'Licensed', 'license_expires_at' => 20.days.from_now.iso8601 })
      create(:collection_asset, collection: collection, asset: expiring)
      create(:collection_asset, collection: collection, asset: safe)

      expect(collection.compliance_violations).to include(
        a_hash_including(asset_id: expiring.id, reason: 'Asset license expires before the campaign workspace TTL finishes.')
      )
      expect(collection.compliance_violations).not_to include(a_hash_including(asset_id: safe.id))
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

  describe '#generate_share_token / .find_by_share_token' do
    it 'mints a signed token that resolves back to the same collection' do
      collection = create(:collection)
      token = collection.generate_share_token

      expect(token).to be_present
      expect(Collection.find_by_share_token(token)).to eq(collection)
    end

    it 'returns nil for a tampered or garbage token' do
      collection = create(:collection)
      token = collection.generate_share_token

      expect(Collection.find_by_share_token("#{token}tampered")).to be_nil
      expect(Collection.find_by_share_token('not-a-real-token')).to be_nil
    end

    it 'returns nil once the token has expired' do
      collection = create(:collection)
      token = collection.generate_share_token(expires_in: 1.second)

      travel_to(2.seconds.from_now) do
        expect(Collection.find_by_share_token(token)).to be_nil
      end
    end

    it 'is not honoured by a signed_id minted for a different purpose' do
      collection = create(:collection)
      unrelated_token = collection.signed_id(purpose: :something_else)

      expect(Collection.find_by_share_token(unrelated_token)).to be_nil
    end

    it 'still resolves a token minted for a subsequently soft-deleted collection (controller decides whether to honour it)' do
      collection = create(:collection)
      token = collection.generate_share_token
      collection.update!(deleted_at: 1.day.ago)

      expect(Collection.find_by_share_token(token)).to eq(collection)
    end
  end
end
