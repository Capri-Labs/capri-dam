# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ReviewGuest, type: :model do
  let(:user)  { create(:user) }
  let(:asset) { create(:asset, user: user) }
  let(:link)  { ReviewLink.mint(target: asset, created_by: user, name: 'Review').first }

  describe '.identify!' do
    it 'normalises the address and reuses the identity on return' do
      first = described_class.identify!(review_link: link, email: '  Priya@Client.COM ', name: 'Priya')
      expect(first.email).to eq('priya@client.com')

      second = described_class.identify!(review_link: link, email: 'priya@client.com')
      expect(second.id).to eq(first.id)
      expect(second.name).to eq('Priya')
    end

    it 'keeps identities separate per link, so one link does not vouch for another' do
      other_link, = ReviewLink.mint(target: asset, created_by: user, name: 'Second review')

      a = described_class.identify!(review_link: link, email: 'priya@client.com')
      b = described_class.identify!(review_link: other_link, email: 'priya@client.com')

      expect(a.id).not_to eq(b.id)
    end

    it 'rejects a malformed address' do
      expect {
        described_class.identify!(review_link: link, email: 'not-an-email')
      }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it 'refuses a self-asserted claim on the reserved anonymous domain' do
      squatter = described_class.anonymous!(review_link: link)

      expect {
        described_class.identify!(review_link: link, email: squatter.email, name: 'Impostor')
      }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe '.anonymous!' do
    it 'mints a distinct, unroutable identity per reviewer' do
      a = described_class.anonymous!(review_link: link)
      b = described_class.anonymous!(review_link: link)

      expect(a.id).not_to eq(b.id)
      expect(a).to be_anonymous
      expect(a.email).to end_with(described_class::ANONYMOUS_DOMAIN)
      expect(a.display_name).to eq('Guest reviewer')
    end
  end

  describe '#display_name' do
    it 'prefers a name and falls back to the address for a known guest' do
      named = described_class.identify!(review_link: link, email: 'priya@client.com', name: 'Priya')
      bare  = described_class.identify!(review_link: link, email: 'sam@client.com')

      expect(named.display_name).to eq('Priya')
      expect(bare.display_name).to eq('sam@client.com')
      expect(bare).not_to be_anonymous
    end
  end
end
