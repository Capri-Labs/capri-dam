require 'rails_helper'

RSpec.describe SystemConfiguration, type: :model do
  before do
    allow(Sidekiq).to receive(:redis).and_yield(instance_double("Redis", publish: true))
  end

  describe 'validations' do
    it 'is valid with valid attributes' do
      expect(build(:system_configuration)).to be_valid
    end

    it 'requires a unique key' do
      create(:system_configuration, key: 'max_upload_mb')
      expect(build(:system_configuration, key: 'max_upload_mb')).not_to be_valid
    end

    it 'requires a recognised data_type' do
      expect(build(:system_configuration, data_type: 'blob')).not_to be_valid
    end
  end

  describe '.get' do
    it 'returns the value cast to string type' do
      create(:system_configuration, key: 'site_name', data_type: 'string', value: 'Capri DAM')
      expect(SystemConfiguration.get('site_name')).to eq('Capri DAM')
    end

    it 'returns the value cast to integer type' do
      create(:system_configuration, key: 'max_mb', data_type: 'integer', value: '500')
      expect(SystemConfiguration.get('max_mb')).to eq(500)
    end

    it 'returns the value cast to boolean type' do
      create(:system_configuration, key: 'debug', data_type: 'boolean', value: 'true')
      expect(SystemConfiguration.get('debug')).to be(true)
    end

    it 'returns default when key is absent' do
      expect(SystemConfiguration.get('missing', default: 'fallback')).to eq('fallback')
    end

    it 'reverts expired values to the fallback before returning them' do
      config = create(
        :system_configuration,
        key: 'banner_message',
        value: 'stale',
        fallback_value: 'fresh',
        expires_at: 5.minutes.ago
      )

      expect(SystemConfiguration.get('banner_message')).to eq('fresh')
      expect(config.reload.value).to eq('fresh')
      expect(config.expires_at).to be_nil
    end
  end

  describe '#cast_value' do
    let(:sc) { build(:system_configuration, data_type: 'json', value: '{"x":1}') }

    it 'parses valid JSON' do
      expect(sc.cast_value(sc.value)).to eq({ 'x' => 1 })
    end

    it 'returns empty hash for invalid JSON' do
      expect(sc.cast_value('not json')).to eq({})
    end
  end
end
