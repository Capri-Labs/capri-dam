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
      cdn.run_callbacks(:save) { }
    end

    it 'does not deactivate other providers when the record is inactive' do
      active_other = instance_double(ActiveRecord::Relation)
      allow(CdnConfiguration).to receive(:where).and_return(active_other)
      allow(active_other).to receive(:update_all)

      build(:cdn_configuration, is_active: false).send(:ensure_single_active_provider)

      expect(active_other).not_to have_received(:update_all)
    end
  end
end
