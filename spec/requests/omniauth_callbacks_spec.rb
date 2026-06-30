require 'rails_helper'

# OmniAuth test mode is configured globally in spec/support/*.
# Tests mock the Keycloak auth hash via OmniAuth.config.mock_auth.
#
# Routes exercised:
#   GET  /users/auth/keycloak_openid          → initiates redirect (handled by OmniAuth middleware)
#   GET  /users/auth/keycloak_openid/callback → Users::OmniauthCallbacksController#keycloak_openid
#   GET  /users/auth/failure                  → Users::OmniauthCallbacksController#failure

RSpec.describe "Users::OmniauthCallbacks", type: :request do
  # ── Helpers ──────────────────────────────────────────────────────────────────

  def mock_keycloak_auth(overrides = {})
    OmniAuth.config.mock_auth[:keycloak_openid] = OmniAuth::AuthHash.new(
      {
        provider: "keycloak_openid",
        uid:      "kc-uid-100",
        info: OmniAuth::AuthHash::InfoHash.new(
          email:      "sso@example.com",
          name:       "SSO User",
          first_name: "SSO",
          last_name:  "User",
          image:      "https://kc.example.com/avatar.png",
        ),
      }.deep_merge(overrides)
    )
    # Always sync env_config after updating mock_auth so the OmniAuth middleware
    # sees the current hash regardless of before-block execution order.
    Rails.application.env_config["omniauth.auth"] =
      OmniAuth.config.mock_auth[:keycloak_openid]
  end

  before do
    OmniAuth.config.test_mode = true
  end

  after do
    OmniAuth.config.mock_auth[:keycloak_openid] = nil
    OmniAuth.config.test_mode = false
  end

  # ── Successful SSO login ──────────────────────────────────────────────────

  describe "GET /users/auth/keycloak_openid/callback" do
    context "when the user does not exist yet (first-time SSO login)" do
      before { mock_keycloak_auth }

      it "creates a new user" do
        expect {
          get "/users/auth/keycloak_openid/callback"
        }.to change(User, :count).by(1)
      end

      it "redirects to the authenticated root" do
        get "/users/auth/keycloak_openid/callback"
        expect(response).to redirect_to(authenticated_root_path)
      end

      it "sets the user's name, first_name, last_name and avatar_url from the token" do
        get "/users/auth/keycloak_openid/callback"
        user = User.find_by(uid: "kc-uid-100")
        expect(user.name).to       eq("SSO User")
        expect(user.first_name).to eq("SSO")
        expect(user.last_name).to  eq("User")
        expect(user.avatar_url).to eq("https://kc.example.com/avatar.png")
      end

      it "derives a username from the email local-part" do
        get "/users/auth/keycloak_openid/callback"
        expect(User.find_by(uid: "kc-uid-100").username).to eq("sso_sso")
      end
    end

    context "when the user already exists (returning SSO login)" do
      let!(:existing_user) do
        create(:user, :sso, uid: "kc-uid-100", provider: "keycloak_openid",
               name: "Old Name", first_name: "Old", last_name: "Name")
      end

      before { mock_keycloak_auth }

      it "does not create a duplicate user" do
        expect {
          get "/users/auth/keycloak_openid/callback"
        }.not_to change(User, :count)
      end

      it "syncs the name from the token" do
        get "/users/auth/keycloak_openid/callback"
        expect(existing_user.reload.name).to eq("SSO User")
      end

      it "syncs first_name and last_name from the token" do
        get "/users/auth/keycloak_openid/callback"
        expect(existing_user.reload.first_name).to eq("SSO")
        expect(existing_user.reload.last_name).to  eq("User")
      end

      it "redirects to the authenticated root" do
        get "/users/auth/keycloak_openid/callback"
        expect(response).to redirect_to(authenticated_root_path)
      end
    end

    context "when the SSO token has no name (only email)" do
      before do
        mock_keycloak_auth(
          uid:  "kc-uid-200",
          info: { email: "noname@example.com", name: nil, first_name: nil, last_name: nil, image: nil }
        )
        Rails.application.env_config["omniauth.auth"] =
          OmniAuth.config.mock_auth[:keycloak_openid]
      end

      it "falls back to the email local-part as the name" do
        get "/users/auth/keycloak_openid/callback"
        expect(User.find_by(uid: "kc-uid-200").name).to eq("noname")
      end
    end

    context "when a username collision would otherwise occur" do
      before do
        # Pre-create a user who already owns the candidate username
        create(:user, username: "sso_sso")
        mock_keycloak_auth
        Rails.application.env_config["omniauth.auth"] =
          OmniAuth.config.mock_auth[:keycloak_openid]
      end

      it "creates the user with a unique suffixed username" do
        get "/users/auth/keycloak_openid/callback"
        user = User.find_by(uid: "kc-uid-100")
        expect(user).not_to be_nil
        expect(user.username).to eq("sso_sso_2")
      end
    end

    context "when the SSO user is deactivated in the DAM" do
      let!(:deactivated_user) do
        create(:user, :sso, :inactive,
               uid: "kc-uid-100", provider: "keycloak_openid")
      end

      before { mock_keycloak_auth }

      it "redirects to the sign-in page with an error" do
        get "/users/auth/keycloak_openid/callback"
        expect(response).to redirect_to(new_user_session_path)
      end

      it "does not sign the user in" do
        get "/users/auth/keycloak_openid/callback"
        follow_redirect!
        expect(response.body).to include("deactivated")
      end
    end
  end

  # ── OmniAuth failure ─────────────────────────────────────────────────────

  describe "GET /users/auth/failure" do
    before do
      OmniAuth.config.mock_auth[:keycloak_openid] = :access_denied
      Rails.application.env_config["omniauth.auth"] =
        OmniAuth.config.mock_auth[:keycloak_openid]
    end

    it "redirects to the sign-in page" do
      get "/users/auth/failure"
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
