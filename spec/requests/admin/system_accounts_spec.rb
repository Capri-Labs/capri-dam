require 'rails_helper' # Notice we use rails_helper here, not swagger_helper

RSpec.describe 'Admin::SystemAccounts', type: :request do
  # Set up an admin user via the factory (ensures required attrs like `name`).
  let(:admin_user) { create(:user, email: 'admin@example.com', admin: true) }

  before do
    # Assuming you are using Devise for web session authentication
    sign_in admin_user
  end

  describe 'GET /admin/system_accounts/new' do
    it 'renders the new form successfully' do
      get new_admin_system_account_path

      expect(response).to have_http_status(:success)
      # Ensures the controller instantiated the @app variable
      expect(assigns(:app)).to be_a_new(Doorkeeper::Application)
    end
  end

  describe 'POST /admin/system_accounts' do
    context 'with valid parameters' do
      let(:valid_params) do
        { doorkeeper_application: { name: 'Zapier Integration' } }
      end

      it 'creates a new Doorkeeper Application and redirects to settings' do
        expect {
          post admin_system_accounts_path, params: valid_params
        }.to change(Doorkeeper::Application, :count).by(1)

        # Verify the machine-to-machine defaults were set
        new_app = Doorkeeper::Application.last
        expect(new_app.redirect_uri).to eq('urn:ietf:wg:oauth:2.0:oob')
        expect(new_app.scopes.to_s).to eq('read write')

        # Verify the redirect
        expect(response).to redirect_to(settings_path)
        expect(flash[:notice]).to include("created")
      end
    end

    context 'with invalid parameters' do
      let(:invalid_params) do
        { doorkeeper_application: { name: '' } } # Name is usually required by Doorkeeper
      end

      it 'does not create an application and re-renders the new template' do
        expect {
          post admin_system_accounts_path, params: invalid_params
        }.not_to change(Doorkeeper::Application, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'GET /admin/system_accounts/:id' do
    let(:oauth_app) do
      Doorkeeper::Application.create!(
        name: 'Test App',
        redirect_uri: 'urn:ietf:wg:oauth:2.0:oob',
        scopes: 'read write'
      )
    end

    it 'renders the show page successfully' do
      get admin_system_account_path(oauth_app)

      expect(response).to have_http_status(:success)
      expect(assigns(:app)).to eq(oauth_app)
    end
  end

  describe 'DELETE /admin/system_accounts/:id' do
    let!(:oauth_app) do
      Doorkeeper::Application.create!(
        name: 'App to Delete',
        redirect_uri: 'urn:ietf:wg:oauth:2.0:oob',
        scopes: 'read write'
      )
    end

    it 'destroys the application and redirects' do
      expect {
        delete admin_system_account_path(oauth_app)
      }.to change(Doorkeeper::Application, :count).by(-1)

      expect(response).to redirect_to(settings_path)
      expect(flash[:notice]).to include("revoked successfully")
    end
  end
end