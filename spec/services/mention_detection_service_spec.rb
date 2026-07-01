require 'rails_helper'

RSpec.describe MentionDetectionService do
  describe '.extract_mentions' do
    let!(:alice) { create(:user, username: 'alice') }
    let!(:john) { create(:user, username: 'john') }

    it 'extracts @username mentions from text' do
      mentions = described_class.extract_mentions('Hello @alice and @john')

      expect(mentions.map { |mention| mention[:user] }).to contain_exactly(alice, john)
    end

    it 'does not produce false positives for email addresses' do
      mentions = described_class.extract_mentions('Email alice@example.com for help')

      expect(mentions).to be_empty
    end

    it 'returns user objects' do
      mention = described_class.extract_mentions('Hi @alice').first

      expect(mention[:user]).to eq(alice)
      expect(mention[:username]).to eq('alice')
    end

    it 'deduplicates repeated mentions' do
      mentions = described_class.extract_mentions('@alice thanks @alice')

      expect(mentions.size).to eq(1)
      expect(mentions.first[:user]).to eq(alice)
    end
  end
end
