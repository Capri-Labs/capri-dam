require 'rails_helper'

RSpec.describe Setting, type: :model do
  describe 'validations' do
    it 'is valid with a unique key' do
      expect(build(:setting)).to be_valid
    end

    it 'requires a unique key' do
      create(:setting, key: 'smtp_host')
      expect(build(:setting, key: 'smtp_host')).not_to be_valid
    end
  end

  describe '.set and .get' do
    it 'round-trips a hash value' do
      Setting.set('test_config', { 'port' => 587 })
      expect(Setting.get('test_config')).to eq({ 'port' => 587 })
    end

    it 'returns nil for an unknown key' do
      expect(Setting.get('no_such_key')).to be_nil
    end
  end

  describe '.get_provider_config' do
    it 'masks secret keys before returning' do
      Setting.set('storage_config_aws', { 'bucket' => 'my-bucket', 'secret_key' => 'abc123' })
      config = Setting.get_provider_config('aws')
      expect(config['secret_key']).to eq('********')
      expect(config['bucket']).to eq('my-bucket')
    end
  end
end
