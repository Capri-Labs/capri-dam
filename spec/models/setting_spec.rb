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

    it 'unwraps values stored in the safety dictionary shape' do
      Setting.set('wrapped_config', { val: { 'enabled' => true } })

      expect(Setting.get('wrapped_config')).to eq({ 'enabled' => true })
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

    it 'parses JSON strings and masks secret-looking keys case-insensitively' do
      Setting.set('storage_config_azure', '{"container":"assets","ClientSecret":"hidden"}')

      expect(Setting.get_provider_config('azure')).to eq('container' => 'assets', 'ClientSecret' => '********')
    end

    it 'returns an empty hash for invalid JSON or unsupported values' do
      Setting.set('storage_config_bad_json', '{nope')
      Setting.set('storage_config_array', [ 'not', 'a', 'hash' ])

      expect(Setting.get_provider_config('bad_json')).to eq({})
      expect(Setting.get_provider_config('array')).to eq({})
    end
  end

  describe '.apply_smtp_settings!' do
    around do |example|
      original_delivery_method = ActionMailer::Base.delivery_method
      original_smtp_settings = ActionMailer::Base.smtp_settings
      example.run
      ActionMailer::Base.delivery_method = original_delivery_method
      ActionMailer::Base.smtp_settings = original_smtp_settings
    end

    it 'does nothing when SMTP settings are blank or disabled' do
      allow(described_class).to receive(:get).with('smtp_settings').and_return(nil, { 'enabled' => 'false' })

      described_class.apply_smtp_settings!
      expect { described_class.apply_smtp_settings! }.not_to change(ActionMailer::Base, :delivery_method)
    end

    it 'applies enabled SMTP settings with normalized types' do
      allow(described_class).to receive(:get).with('smtp_settings').and_return(
        'enabled' => 'true',
        'address' => 'smtp.example.com',
        'port' => '2525',
        'domain' => 'example.com',
        'user_name' => 'mailer',
        'password' => 'secret',
        'authentication' => 'login',
        'enable_starttls_auto' => 'true'
      )

      described_class.apply_smtp_settings!

      expect(ActionMailer::Base.delivery_method).to eq(:smtp)
      expect(ActionMailer::Base.smtp_settings).to include(
        address: 'smtp.example.com',
        port: 2525,
        authentication: :login,
        enable_starttls_auto: true
      )
    end

    it 'defaults SMTP authentication to plain when unspecified' do
      allow(described_class).to receive(:get).with('smtp_settings').and_return(
        'enabled' => 'true',
        'address' => 'smtp.example.com',
        'port' => '25'
      )

      described_class.apply_smtp_settings!

      expect(ActionMailer::Base.smtp_settings[:authentication]).to eq(:plain)
      expect(ActionMailer::Base.smtp_settings[:enable_starttls_auto]).to be(false)
    end
  end
end
