require 'rails_helper'

RSpec.describe CommentWebhookSubscription, type: :model do
  def build_subscription(url)
    described_class.new(name: 'Proofing vendor', url: url)
  end

  describe 'url validation' do
    it 'accepts http and https endpoints' do
      expect(build_subscription('https://vendor.example/hooks/capri')).to be_valid
      expect(build_subscription('http://vendor.example/hooks/capri')).to be_valid
    end

    it 'rejects a non-http scheme' do
      subscription = build_subscription('ftp://vendor.example')
      expect(subscription).not_to be_valid
      expect(subscription.errors[:url]).to include('must be an http(s) URL')
    end

    it 'requires a url' do
      expect(build_subscription(nil)).not_to be_valid
    end

    # The previous validation only anchored the start of the string, so anything
    # was accepted as long as it began with "http". The URL is handed to Faraday
    # by CommentWebhookWorker, which makes a trailing newline header-injection
    # material rather than a cosmetic problem.
    it 'rejects a url carrying an embedded newline' do
      subscription = build_subscription("https://vendor.example/hook\nX-Injected: 1")
      expect(subscription).not_to be_valid
      expect(subscription.errors[:url]).to include('must be an http(s) URL')
    end

    it 'rejects a scheme with no host' do
      expect(build_subscription('https://')).not_to be_valid
    end

    it 'rejects an unparseable url' do
      expect(build_subscription('https://vendor.example/a b')).not_to be_valid
    end
  end

  describe 'secret generation' do
    it 'generates a secret on create when none is supplied' do
      subscription = described_class.create!(name: 'Tracker', url: 'https://tracker.example/hook')
      expect(subscription.secret).to be_present
    end
  end
end
