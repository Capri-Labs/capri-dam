# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ReviewLink, type: :model do
  let(:user)       { create(:user) }
  let(:asset)      { create(:asset, user: user, title: 'Hero shot') }
  let(:collection) { create(:collection, user: user, name: 'Autumn campaign') }

  describe '.mint' do
    it 'returns the raw token and stores only its digest' do
      link, token = described_class.mint(target: asset, created_by: user, name: 'Review')

      expect(token.length).to eq(43)
      expect(link.token_digest).to eq(Digest::SHA256.hexdigest(token))
      # The raw token must not be recoverable from the row.
      expect(link.attributes.values.map(&:to_s)).not_to include(token)
    end

    it 'defaults the expiry rather than leaving the link open ended' do
      link, = described_class.mint(target: asset, created_by: user, name: 'Review')
      expect(link.expires_at).to be_within(1.minute).of(described_class::DEFAULT_EXPIRY.from_now)
    end

    it 'refuses an expiry beyond the hard cap' do
      expect {
        described_class.mint(target: asset, created_by: user, name: 'Forever', expires_at: 2.years.from_now)
      }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it 'refuses anything that is not an asset or a collection' do
      expect {
        described_class.mint(target: user, created_by: user, name: 'Wrong')
      }.to raise_error(ArgumentError)
    end
  end

  describe '.find_by_token' do
    it 'resolves a real token and nothing else' do
      link, token = described_class.mint(target: asset, created_by: user, name: 'Review')

      expect(described_class.find_by_token(token)).to eq(link)
      expect(described_class.find_by_token('not-a-token')).to be_nil
      expect(described_class.find_by_token(nil)).to be_nil
      expect(described_class.find_by_token('')).to be_nil
    end
  end

  describe 'usability' do
    it 'is usable while live' do
      link, = described_class.mint(target: asset, created_by: user, name: 'Review')
      expect(link).to be_usable
      expect(link.unusable_reason).to be_nil
      expect(described_class.live).to include(link)
    end

    it 'reports revocation' do
      link, = described_class.mint(target: asset, created_by: user, name: 'Review')
      link.revoke!

      expect(link).not_to be_usable
      expect(link.unusable_reason).to eq(:revoked)
      expect(described_class.live).not_to include(link)
    end

    it 'reports expiry' do
      link, = described_class.mint(target: asset, created_by: user, name: 'Review')
      link.update_column(:expires_at, 1.hour.ago)

      expect(link.reload.unusable_reason).to eq(:expired)
      expect(described_class.live).not_to include(link)
    end
  end

  describe 'targets' do
    it 'rejects a link with no target' do
      expect {
        described_class.create!(name: 'Nothing', created_by: user, token_digest: 'x', expires_at: 1.day.from_now)
      }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it 'rejects a link with two targets' do
      link = described_class.new(name: 'Both', created_by: user, token_digest: 'x',
                                 expires_at: 1.day.from_now, asset: asset, collection: collection)
      expect(link).not_to be_valid
    end

    it 'clears the other target on reassignment' do
      link, = described_class.mint(target: asset, created_by: user, name: 'Review')
      link.target = collection

      expect(link.asset_id).to be_nil
      expect(link.collection_id).to eq(collection.id)
    end
  end

  describe '#scoped_assets and #covers?' do
    it 'covers exactly the one asset for an asset link' do
      other = create(:asset, user: user)
      link, = described_class.mint(target: asset, created_by: user, name: 'Review')

      expect(link.scoped_assets.to_a).to eq([ asset ])
      expect(link.covers?(asset.id)).to be(true)
      expect(link.covers?(other.id)).to be(false)
      expect(link.covers?(nil)).to be(false)
    end

    it 'follows live collection membership rather than a snapshot' do
      collection.assets << asset
      link, = described_class.mint(target: collection, created_by: user, name: 'Review')
      expect(link.covers?(asset.id)).to be(true)

      # Removing the asset withdraws it from every outstanding link at once,
      # which is the behaviour that makes curation a usable access control.
      collection.assets.destroy(asset)
      expect(link.reload.covers?(asset.id)).to be(false)
    end
  end

  describe '#passphrase' do
    it 'stores a digest and matches correctly' do
      link, = described_class.mint(target: asset, created_by: user, name: 'Review')
      link.passphrase = 'open sesame'
      link.save!

      expect(link.passphrase_digest).not_to include('open sesame')
      expect(link).to be_passphrase_required
      expect(link.passphrase_matches?('open sesame')).to be(true)
      expect(link.passphrase_matches?('wrong')).to be(false)
      expect(link.passphrase_matches?(nil)).to be(false)
    end

    it 'admits anything when no passphrase is set, because there is no gate' do
      link, = described_class.mint(target: asset, created_by: user, name: 'Review')

      expect(link).not_to be_passphrase_required
      expect(link.passphrase_matches?('anything')).to be(true)
    end

    it 'clears the passphrase when set to blank' do
      link, = described_class.mint(target: asset, created_by: user, name: 'Review')
      link.passphrase = 'secret'
      link.save!
      link.passphrase = ''
      link.save!

      expect(link.reload).not_to be_passphrase_required
    end
  end

  describe '#record_access!' do
    it 'counts opens without being able to fail the request' do
      link, = described_class.mint(target: asset, created_by: user, name: 'Review')

      expect { link.record_access! }.to change { link.reload.access_count }.from(0).to(1)
      expect(link.last_accessed_at).to be_present
    end
  end

  describe '#target_label' do
    it 'names whichever target it has' do
      asset_link, = described_class.mint(target: asset, created_by: user, name: 'A')
      collection_link, = described_class.mint(target: collection, created_by: user, name: 'C')

      expect(asset_link.target_label).to eq('Hero shot')
      expect(collection_link.target_label).to eq('Autumn campaign')
    end
  end
end
