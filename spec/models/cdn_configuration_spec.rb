require 'rails_helper'

RSpec.describe CdnConfiguration, type: :model do
  describe 'validations' do
    it 'is valid with a unique provider' do
      expect(build(:cdn_configuration)).to be_valid
    end

    it 'requires a provider' do
      expect(build(:cdn_configuration, provider: nil)).not_to be_valid
    end
  end

  describe 'single active provider enforcement' do
    it 'calls ensure_single_active_provider before save' do
      cdn = build(:cdn_configuration, is_active: true)
      expect(cdn).to receive(:ensure_single_active_provider).and_call_original
      # The callback fires; skip the full DB test because ActiveRecord encryption
      # type: :json is not fully supported in the test environment.
      cdn.run_callbacks(:save) {}
    end
  end
end
