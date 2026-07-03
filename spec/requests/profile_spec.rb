require "rails_helper"

RSpec.describe "Profile API", type: :request do
  let(:user)  { create(:user) }
  let(:admin) { create(:user, :admin) }

  before { sign_in user }

  # ── GET /profile ─────────────────────────────────────────────────────────────

  describe "GET /profile" do
    it "renders the profile page (HTML)" do
      get profile_path
      expect(response).to have_http_status(:ok)
    end
  end

  # ── PATCH /profile ────────────────────────────────────────────────────────────

  describe "PATCH /profile" do
    it "updates allowed profile fields" do
      patch profile_path, params: { user: { first_name: "Jane", department: "Marketing" } },
                          as: :json
      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["success"]).to be true
      expect(user.reload.first_name).to eq("Jane")
      expect(user.reload.department).to eq("Marketing")
    end

    context "when user is SSO-managed" do
      let(:user) { create(:user, :sso) }

      it "silently ignores first_name and email changes" do
        original_email = user.email
        patch profile_path,
              params: { user: { first_name: "Hacker", email: "hacked@evil.com" } },
              as: :json
        expect(response).to have_http_status(:ok)
        expect(user.reload.email).to eq(original_email)
      end
    end
  end

  # ── PATCH /profile/preferences ────────────────────────────────────────────────

  describe "PATCH /profile/preferences" do
    it "saves language and theme" do
      patch preferences_profile_path,
            params: { preferences: { language: "de", theme: "dark" } },
            as: :json
      expect(response).to have_http_status(:ok)
      pref = user.reload.preference
      expect(pref.language).to eq("de")
      expect(pref.theme).to eq("dark")
    end

    it "silently ignores a timezone param (not user-managed)" do
      patch preferences_profile_path,
            params: { preferences: { language: "fr", timezone: "America/New_York" } },
            as: :json
      expect(response).to have_http_status(:ok)
      # timezone must NOT have been persisted
      expect(user.reload.preference.timezone).not_to eq("America/New_York")
    end

    it "rejects an unsupported theme" do
      patch preferences_profile_path,
            params: { preferences: { theme: "neon-toxic" } },
            as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "does not expose timezone in the response" do
      patch preferences_profile_path,
            params: { preferences: { language: "es" } },
            as: :json
      json = response.parsed_body
      expect(json["preferences"]).not_to have_key("timezone")
    end
  end

  # ── PATCH /profile/password ───────────────────────────────────────────────────

  describe "PATCH /profile/password" do
    it "updates the password when current_password matches" do
      patch password_profile_path,
            params: {
              current_password:              "password123",
              new_password:                  "NewP@ss456",
              new_password_confirmation:     "NewP@ss456",
            },
            as: :json
      expect(response).to have_http_status(:ok)
      expect(user.reload.valid_password?("NewP@ss456")).to be true
    end

    it "returns 422 when current_password is wrong" do
      patch password_profile_path,
            params: { current_password: "wrong", new_password: "x", new_password_confirmation: "x" },
            as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    context "when user is SSO-managed" do
      let(:user) { create(:user, :sso) }

      it "returns 422" do
        patch password_profile_path,
              params: { current_password: "p", new_password: "p2", new_password_confirmation: "p2" },
              as: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  # ── GET /profile/activity.json ────────────────────────────────────────────────

  describe "GET /profile/activity.json" do
    before do
      Current.user      = user
      Current.true_user = user
      create_list(:audit_log, 3, user: user, action: "create", auditable_type: "Asset", auditable_id: 1)
    end

    it "returns the user's own activity logs" do
      get activity_profile_path, as: :json
      json = response.parsed_body
      expect(json["activity"].size).to eq(3)
      expect(json["total"]).to eq(3)
    end
  end

  # ── Personal Access Tokens ────────────────────────────────────────────────────

  describe "POST /profile/personal_access_tokens" do
    it "creates a token and returns the raw token once" do
      post profile_personal_access_tokens_path,
           params: { token: { name: "CI Pipeline", scopes: "read" } },
           as: :json
      expect(response).to have_http_status(:created)
      json = response.parsed_body
      expect(json["success"]).to be true
      expect(json["token"]["raw_token"]).to start_with("dat_")
    end

    it "returns 422 if name is blank" do
      post profile_personal_access_tokens_path,
           params: { token: { name: "" } }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "DELETE /profile/personal_access_tokens/:id" do
    let!(:pat) do
      p, _ = PersonalAccessToken.generate_for(user, name: "Revokable")
      p
    end

    it "revokes the token" do
      delete profile_personal_access_token_path(pat), as: :json
      expect(response).to have_http_status(:ok)
      expect(pat.reload.active).to be false
    end

    it "returns 404 for a token belonging to another user" do
      other_pat, _ = PersonalAccessToken.generate_for(create(:user), name: "Other")
      delete profile_personal_access_token_path(other_pat), as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "additional failure branches" do
    it "returns validation errors for invalid profile updates" do
      patch profile_path, params: { user: { email: '' } }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['errors']).to include("Email can't be blank")
    end

    it "returns validation errors when the new password is invalid" do
      patch password_profile_path,
            params: {
              current_password: 'password123',
              new_password: 'short',
              new_password_confirmation: 'short',
            },
            as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['errors']).not_to be_empty
    end

    it "serializes last_used_at on personal access token index responses" do
      token = create(:personal_access_token, user: user, last_used_at: Time.zone.parse('2026-07-01T10:00:00Z'))

      get profile_personal_access_tokens_path, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['tokens']).to include(
        a_hash_including('id' => token.id, 'last_used_at' => '2026-07-01T10:00:00Z')
      )
    end
  end
end
