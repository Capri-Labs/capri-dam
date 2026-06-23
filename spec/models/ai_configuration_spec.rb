require 'rails_helper'

RSpec.describe AiConfiguration, type: :model do
  describe 'validations' do
    it 'is valid with an active_provider' do
      expect(build(:ai_configuration)).to be_valid
    end

    it 'requires an active_provider' do
      expect(build(:ai_configuration, active_provider: nil)).not_to be_valid
    end
  end

  describe '.current' do
    it 'returns the existing record or creates one' do
      AiConfiguration.delete_all
      config = AiConfiguration.current
      expect(config).to be_persisted
      expect(config.active_provider).to eq('openai')
      # idempotent
      expect(AiConfiguration.current.id).to eq(config.id)
    end
  end

  describe 'broadcast resilience' do
    it 'does not raise when Redis is unavailable' do
      allow(Sidekiq).to receive(:redis).and_raise(Redis::BaseConnectionError.new('down'))
      expect { create(:ai_configuration) }.not_to raise_error
    end
  end
end
