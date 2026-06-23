require 'rails_helper'

RSpec.describe StorageBackend, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      expect(build(:storage_backend)).to be_valid
    end

    it 'requires a name' do
      expect(build(:storage_backend, name: nil)).not_to be_valid
    end

    it 'requires a valid provider_type' do
      expect(build(:storage_backend, provider_type: 'unknown_provider')).not_to be_valid
    end

    it 'accepts all documented provider types' do
      StorageBackend::PROVIDER_TYPES.each do |type|
        expect(build(:storage_backend, provider_type: type)).to be_valid
      end
    end
  end

  describe '#masked_configuration' do
    it 'masks keys matching secret/key/password/token/credentials' do
      backend = build(:storage_backend,
                      configuration: { 'access_key' => 'AKID', 'bucket' => 'my-bucket' })
      masked = backend.masked_configuration
      expect(masked['access_key']).to eq('********')
      expect(masked['bucket']).to eq('my-bucket')
    end
  end
end
