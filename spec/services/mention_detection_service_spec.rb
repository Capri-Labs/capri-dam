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

# ---- merged from mention_detection_service_coverage_spec.rb ----
RSpec.describe MentionDetectionService do
  describe '.extract_mentions' do
    it 'returns an empty list for blank, missing, or unknown mentions' do
      expect(described_class.extract_mentions(nil)).to eq([])
      expect(described_class.extract_mentions('hello world')).to eq([])
      expect(described_class.extract_mentions('hello @nobody')).to eq([])
    end

    it 'matches by email handle and preserves canonical username fallback' do
      user = create(:user, username: '', email: 'person@example.com')

      mention = described_class.extract_mentions('Please ask @person').first

      expect(mention[:user]).to eq(user)
      expect(mention[:username]).to eq('person')
      expect(mention[:start]).to eq(11)
      expect(mention[:end]).to eq(18)
    end
  end

  describe '.replace_mentions' do
    it 'replaces known handles with escaped mention spans and leaves unknown handles unchanged' do
      user = create(:user)

      html = described_class.replace_mentions('Hi @Alice and @nobody', 'alice' => user)

      expect(html).to include(%(class="mention" data-user-id="#{user.id}"))
      expect(html).to include('@Alice')
      expect(html).to include('@nobody')
    end

    it 'returns blank text unchanged' do
      expect(described_class.replace_mentions(nil)).to be_nil
      expect(described_class.replace_mentions('')).to eq('')
    end
  end
end
