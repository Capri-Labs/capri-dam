require 'rails_helper'

RSpec.describe "Users::Sessions", type: :request do
  let(:user) { create(:user, password: "password123") }

  # ── Standard login ────────────────────────────────────────────────────────

  describe "POST /users/sign_in.json" do
    it "returns success on valid credentials" do
      post "/users/sign_in.json",
           params: { user: { email: user.email, password: "password123" } },
           as: :json

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["success"]).to be true
      expect(json["user"]["email"]).to eq(user.email)
    end

    it "returns unauthorized on invalid password" do
      post "/users/sign_in.json",
           params: { user: { email: user.email, password: "wrong" } },
           as: :json

      expect(response).to have_http_status(:unauthorized)
      json = response.parsed_body
      expect(json["success"]).to be false
      expect(json["error"]).to eq("Invalid email or password")
    end

    it "returns unauthorized for an unknown email" do
      post "/users/sign_in.json",
           params: { user: { email: "nobody@example.com", password: "password123" } },
           as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["success"]).to be false
    end

    context "when the user is deactivated" do
      let(:user) { create(:user, :inactive, password: "password123") }

      it "returns unauthorized" do
        post "/users/sign_in.json",
             params: { user: { email: user.email, password: "password123" } },
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when force_password_change is required" do
      let(:user) { create(:user, password: "temp_pass", force_password_change: true) }

      it "returns a force_password_change indicator without signing in" do
        post "/users/sign_in.json",
             params: { user: { email: user.email, password: "temp_pass" } },
             as: :json

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["success"]).to be true
        expect(json["force_password_change"]).to be true
        expect(json["email"]).to eq(user.email)
      end
    end
  end

  # ── Force password update ─────────────────────────────────────────────────

  describe "POST /users/force_password_update" do
    let(:user) { create(:user, password: "temp_pass", force_password_change: true) }

    it "updates the password and signs the user in when credentials are valid" do
      post "/users/force_password_update",
           params: {
             email:                 user.email,
             current_password:      "temp_pass",
             new_password:          "NewPass123!",
             new_password_confirmation: "NewPass123!",
           },
           as: :json

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["success"]).to be true
      expect(json["user"]["email"]).to eq(user.email)
    end

    it "clears the force_password_change flag after a successful update" do
      post "/users/force_password_update",
           params: {
             email:                    user.email,
             current_password:         "temp_pass",
             new_password:             "NewPass123!",
             new_password_confirmation: "NewPass123!",
           },
           as: :json

      expect(user.reload.force_password_change).to be false
    end

    it "returns unauthorized when the current password is wrong" do
      post "/users/force_password_update",
           params: {
             email:                    user.email,
             current_password:         "wrong_temp",
             new_password:             "NewPass123!",
             new_password_confirmation: "NewPass123!",
           },
           as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["success"]).to be false
    end

    it "returns unprocessable_entity when new passwords do not match" do
      post "/users/force_password_update",
           params: {
             email:                    user.email,
             current_password:         "temp_pass",
             new_password:             "NewPass123!",
             new_password_confirmation: "different",
           },
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["success"]).to be false
    end
  end
end
