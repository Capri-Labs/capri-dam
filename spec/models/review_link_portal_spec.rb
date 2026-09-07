require 'rails_helper'

# The scoping rules a distribution portal rests on. These are the checks that
# decide what an outsider can see, so they are exercised against the real
# relations rather than stubbed.
RSpec.describe ReviewLink, 'distribution portal' do
  let(:user)       { create(:user) }
  let(:collection) { create(:collection, user: user) }

  let(:cleared)    { create(:asset, :externally_distributable, user: user, title: 'Cleared') }
  let(:also_ok)    { create(:asset, :externally_distributable, user: user, title: 'Also OK') }
  let(:ungranted)  { create(:asset, :externally_distributable, user: user, title: 'Ungranted') }
  let(:internal)   { create(:asset, user: user, title: 'Internal', usage_terms: 'internal_only') }
  let(:lapsed)     { create(:asset, :license_expired, user: user, title: 'Lapsed') }

  let(:portal) do
    ReviewLink.mint(target: collection, created_by: user, name: 'Partner portal', kind: 'portal').first
  end

  def grant(asset, permission)
    PortalGrant.create!(review_link: portal, asset: asset, permission: permission)
  end

  before do
    [ cleared, also_ok, ungranted, internal, lapsed ].each { |a| collection.assets << a }
  end

  describe '#scoped_assets' do
    it 'exposes only assets that were explicitly granted' do
      grant(cleared, 'download')
      grant(also_ok, 'view')

      expect(portal.scoped_assets).to contain_exactly(cleared, also_ok)
    end

    it 'is empty when nothing has been granted, rather than defaulting to the whole collection' do
      # Default-deny: a portal that silently shared everything the moment it
      # was created would be the opposite of per-asset permissioning.
      expect(portal.scoped_assets).to be_empty
    end

    it 'withdraws an asset removed from the collection even though its grant survives' do
      grant(cleared, 'download')
      expect(portal.scoped_assets).to contain_exactly(cleared)

      collection.assets.destroy(cleared)

      expect(portal.reload.scoped_assets).to be_empty
      # The grant is deliberately left in place: re-adding the asset to the
      # collection should restore the intent that was already expressed.
      expect(portal.portal_grants.where(asset_id: cleared.id)).to exist
    end

    it 'does not expose an asset added to the collection after the portal was shared' do
      grant(cleared, 'view')
      latecomer = create(:asset, :externally_distributable, user: user, title: 'Latecomer')
      collection.assets << latecomer

      expect(portal.scoped_assets).not_to include(latecomer)
    end

    it 'leaves review links untouched by grants' do
      review = ReviewLink.mint(target: collection, created_by: user, name: 'Review').first

      expect(review.kind).to eq('review')
      expect(review.scoped_assets).to include(cleared, ungranted, internal)
    end
  end

  describe '#distributable_assets' do
    it 'drops granted assets that rights forbid from leaving' do
      grant(cleared, 'download')
      grant(internal, 'download')
      grant(lapsed, 'download')

      # A grant records that the sender is willing; it cannot make an
      # internal-only or lapsed asset lawful to send.
      expect(portal.distributable_assets).to contain_exactly(cleared)
    end
  end

  describe '#may_download?' do
    it 'permits download only where the grant says so' do
      grant(cleared, 'download')
      grant(also_ok, 'view')

      expect(portal.may_download?(cleared)).to be(true)
      expect(portal.may_download?(also_ok)).to be(false)
      expect(portal.may_download?(ungranted)).to be(false)
      expect(portal.may_download?(nil)).to be(false)
    end

    it 'falls back to the link-wide flag for review links' do
      review = ReviewLink.mint(target: collection, created_by: user,
                               name: 'Review', allow_downloads: true).first

      expect(review.may_download?(cleared)).to be(true)
    end
  end

  describe 'validation' do
    it 'rejects an unknown kind' do
      link = ReviewLink.mint(target: collection, created_by: user, name: 'X').first
      link.kind = 'something-else'

      expect(link).not_to be_valid
      expect(link.errors[:kind]).to be_present
    end

    it 'refuses two grants for the same asset on one link' do
      grant(cleared, 'view')

      expect { grant(cleared, 'download') }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it 'rejects an unknown permission' do
      g = PortalGrant.new(review_link: portal, asset: cleared, permission: 'delete')

      expect(g).not_to be_valid
    end
  end
end
