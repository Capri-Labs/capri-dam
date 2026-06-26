require "rails_helper"

RSpec.describe "Impersonation::Sessions", type: :request do
  let(:admin)       { create(:user, :admin) }
  let(:super_admin) { create(:user, :super_admin) }
  let(:regular)     { create(:user) }
  let(:another_admin) { create(:user, :admin) }

  # ── POST /impersonation/start/:user_id ───────────────────────────────────────

  describe "POST /impersonation/start/:user_id" do
    context "as an admin" do
      before { sign_in admin }

      it "starts an impersonation session for a regular user" do
        post impersonation_start_path(user_id: regular.id), as: :json
        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["success"]).to be true
        expect(json["impersonated_user"]["id"]).to eq(regular.id)
      end

      it "writes an audit log entry" do
        expect {
          post impersonation_start_path(user_id: regular.id), as: :json
        }.to change(AuditLog, :count).by(1)
        expect(AuditLog.last.action).to eq("impersonation_start")
      end

      it "returns 403 when trying to impersonate a super-admin" do
        post impersonation_start_path(user_id: super_admin.id), as: :json
        expect(response).to have_http_status(:forbidden)
      end

      it "returns 404 for a non-existent user" do
        post impersonation_start_path(user_id: 999_999), as: :json
        expect(response).to have_http_status(:not_found)
      end
    end

    context "as a super-admin" do
      before { sign_in super_admin }

      it "can impersonate a regular admin" do
        post impersonation_start_path(user_id: admin.id), as: :json
        expect(response).to have_http_status(:ok)
      end

      it "cannot impersonate another super-admin" do
        other_super = create(:user, :super_admin)
        post impersonation_start_path(user_id: other_super.id), as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "as an unauthenticated user" do
      it "redirects to sign-in" do
        post impersonation_start_path(user_id: regular.id), as: :json
        expect(response).to have_http_status(:unauthorized).or have_http_status(:redirect)
      end
    end
  end

  # ── DELETE /impersonation/stop ────────────────────────────────────────────────

  describe "DELETE /impersonation/stop" do
    before do
      sign_in admin
      # Start a session so there's something to stop
      post impersonation_start_path(user_id: regular.id), as: :json
    end

    it "ends the impersonation session" do
      delete impersonation_stop_path, as: :json
      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["success"]).to be true
    end

    it "writes an impersonation_end audit log entry" do
      expect {
        delete impersonation_stop_path, as: :json
      }.to change { AuditLog.where(action: "impersonation_end").count }.by(1)
    end
  end
end
