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
      cdn.run_callbacks(:save) { }
    end

    it 'does not deactivate other providers when the record is inactive' do
      active_other = instance_double(ActiveRecord::Relation)
      allow(CdnConfiguration).to receive(:where).and_return(active_other)
      allow(active_other).to receive(:update_all)

      build(:cdn_configuration, is_active: false).send(:ensure_single_active_provider)

      expect(active_other).not_to have_received(:update_all)
    end

    it 'deactivates the previously active provider when a new one is activated' do
      first = create(:cdn_configuration, provider: 'fastly', is_active: true)
      create(:cdn_configuration, provider: 'cloudflare', is_active: true)

      expect(first.reload.is_active).to be(false)
    end
  end

  describe 'encrypted settings persistence' do
    # Regression test: `encrypts :settings, type: :json` previously raised
    # `NoMethodError: undefined method 'type=' for an instance of
    # ActiveRecord::Encryption::Context` on save, because `type:` is not a
    # valid option for `encrypts` on this Rails version (see the fix in
    # app/models/cdn_configuration.rb — declare the attribute's cast type via
    # `attribute :settings, :json`, then `encrypts :settings` with no extra
    # options, mirroring SystemConnector#credentials_payload).
    it 'round-trips a hash through encryption without raising' do
      cdn = create(:cdn_configuration, settings: { "api_key" => "secret", "image_optimizer_formats" => [ "webp", "avif" ] })

      expect(CdnConfiguration.find(cdn.id).settings).to eq(
        "api_key" => "secret",
        "image_optimizer_formats" => [ "webp", "avif" ]
      )
    end

    it 'stores ciphertext (not plaintext) in the underlying database column' do
      cdn = create(:cdn_configuration, settings: { "api_key" => "super-secret-value" })

      raw_column_value = CdnConfiguration.connection.select_value(
        "SELECT settings FROM cdn_configurations WHERE id = #{cdn.id}"
      )

      expect(raw_column_value).not_to include("super-secret-value")
    end
  end
end
