require 'rails_helper'

RSpec.describe SystemConnector, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      expect(build(:system_connector)).to be_valid
    end

    it 'requires a name' do
      expect(build(:system_connector, name: nil)).not_to be_valid
    end

    it 'requires a valid provider_type' do
      expect(build(:system_connector, provider_type: 'bogus')).not_to be_valid
    end

    it 'requires an http(s) endpoint for non-FTP providers' do
      expect(build(:system_connector, endpoint: 'not-a-url')).not_to be_valid
    end

    it 'allows a bare hostname for FTP providers' do
      expect(build(:system_connector, :ftp)).to be_valid
    end

    it 'requires the JWT payload fields when credential_type is jwt_service_account' do
      connector = build(:system_connector, credential_type: 'jwt_service_account', credentials_payload: {})
      expect(connector).not_to be_valid
      expect(connector.errors[:credentials_payload].first).to include('client_id', 'client_secret')
    end

    it 'is valid when all JWT payload fields are present' do
      connector = build(:system_connector, :jwt_service_account)
      expect(connector).to be_valid
    end
  end

  describe 'before_create callback' do
    it 'auto-generates a webhook_secret' do
      connector = create(:system_connector)
      expect(connector.webhook_secret).to be_present
      expect(connector.webhook_secret.length).to eq(64)
    end
  end

  describe '#provider_label' do
    it 'returns a human-readable label' do
      connector = build(:system_connector, provider_type: 'aem')
      expect(connector.provider_label).to eq('Adobe Experience Manager')
    end
  end

  describe '#test_connection' do
    it 'delegates to IngestionAdapters::Factory.test with the connector credentials' do
      connector = build(:system_connector, provider_type: 'aem')
      expect(IngestionAdapters::Factory).to receive(:test)
        .with('aem', { 'endpoint' => connector.endpoint, 'auth_token' => connector.auth_token })
        .and_return({ success: true })

      expect(connector.test_connection).to eq({ success: true })
    end

    it 'rescues adapter errors and returns a failure hash' do
      connector = build(:system_connector, provider_type: 'aem')
      allow(IngestionAdapters::Factory).to receive(:test).and_raise(StandardError.new('boom'))

      expect(connector.test_connection).to eq({ success: false, message: 'boom' })
    end
  end

  describe 'encryption at rest' do
    it 'stores auth_token as ciphertext, not plaintext, in the raw column' do
      connector = create(:system_connector, auth_token: 'super-secret-token')
      raw = ActiveRecord::Base.connection.select_value("SELECT auth_token FROM system_connectors WHERE id = #{connector.id}")
      expect(raw).not_to include('super-secret-token')
      expect(connector.reload.auth_token).to eq('super-secret-token')
    end

    it 'stores credentials_payload as ciphertext and never exposes it via as_json' do
      connector = create(:system_connector, :jwt_service_account)
      raw = ActiveRecord::Base.connection.select_value("SELECT credentials_payload FROM system_connectors WHERE id = #{connector.id}")
      expect(raw).not_to include('p8e-')

      json = connector.as_json
      expect(json).not_to have_key('credentials_payload')
      expect(json).not_to have_key('access_token')
      expect(json).not_to have_key('auth_token')
    end
  end

  describe '#ensure_fresh_access_token! / #refresh_access_token! / #revoke_token!' do
    it 'returns the plain auth_token unchanged for non-JWT connectors' do
      connector = build(:system_connector, auth_token: 'tok')
      expect(connector.ensure_fresh_access_token!).to eq('tok')
    end

    it 'refreshes and persists a new access token for JWT connectors when none is cached' do
      connector = create(:system_connector, :jwt_service_account)
      allow(Ims::JwtTokenExchangeService).to receive(:new).with(connector).and_return(
        instance_double(Ims::JwtTokenExchangeService, call: { access_token: 'fresh-token', expires_at: 1.hour.from_now })
      )

      token = connector.ensure_fresh_access_token!

      expect(token).to eq('fresh-token')
      expect(connector.reload.token_status).to eq('valid')
      expect(connector.last_token_refreshed_at).to be_present
    end

    it 'does not re-fetch a token that is still valid' do
      connector = create(:system_connector, :jwt_service_account, access_token: 'cached', access_token_expires_at: 1.hour.from_now)
      expect(Ims::JwtTokenExchangeService).not_to receive(:new)

      expect(connector.ensure_fresh_access_token!).to eq('cached')
    end

    it 'records token_status=error and re-raises when the exchange fails' do
      connector = create(:system_connector, :jwt_service_account)
      allow(Ims::JwtTokenExchangeService).to receive(:new).and_return(
        instance_double(Ims::JwtTokenExchangeService, call: nil).tap { |d| allow(d).to receive(:call).and_raise(Ims::JwtTokenExchangeService::Error, "boom") }
      )

      expect { connector.refresh_access_token! }.to raise_error(Ims::JwtTokenExchangeService::Error)
      expect(connector.reload.token_status).to eq('error')
      expect(connector.last_token_error).to eq('boom')
    end

    it 'clears the cached token on revoke' do
      connector = create(:system_connector, :jwt_service_account, access_token: 'cached', access_token_expires_at: 1.hour.from_now)
      connector.revoke_token!

      expect(connector.reload.access_token).to be_nil
      expect(connector.token_status).to eq('revoked')
    end
  end

  describe '#credentials_for_adapter' do
    it 'includes root_path when a source_path is provided' do
      connector = build(:system_connector, auth_token: 'tok', default_source_path: nil)
      creds = connector.credentials_for_adapter(source_path: '/content/dam/US/marketing-assets/product-assets')

      expect(creds).to eq(
        'endpoint'   => connector.endpoint,
        'auth_token' => 'tok',
        'root_path'  => '/content/dam/US/marketing-assets/product-assets'
      )
    end

    it 'falls back to default_source_path when no override is given' do
      connector = build(:system_connector, auth_token: 'tok', default_source_path: '/content/dam/default')
      expect(connector.credentials_for_adapter['root_path']).to eq('/content/dam/default')
    end
  end
end
