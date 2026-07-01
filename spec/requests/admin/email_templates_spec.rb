require "rails_helper"

RSpec.describe "Admin::EmailTemplates", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:user) { create(:user) }
  let!(:template) { create(:email_template, name: "Welcome", event_trigger: "user_created") }

  describe "GET /admin/email_templates" do
    it "redirects unauthenticated users to sign in" do
      get admin_email_templates_path, as: :json

      expect(response).to redirect_to(new_user_session_path(format: :json))
    end

    it "returns forbidden for non-admin users" do
      sign_in user

      get admin_email_templates_path, as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "returns the templates for admins" do
      sign_in admin

      get admin_email_templates_path, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("email_templates", 0, "name")).to eq("Welcome")
    end
  end

  describe "GET /admin/email_templates/:id" do
    it "returns the requested template for admins" do
      sign_in admin

      get admin_email_template_path(template), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("email_template", "event_trigger")).to eq("user_created")
    end
  end

  describe "POST /admin/email_templates" do
    let(:valid_params) do
      {
        email_template: {
          name: "Digest",
          event_trigger: "daily_digest",
          subject: "Digest for {{ user.first_name }}",
          html_body: "<p>Hi</p>",
          text_body: "Hi",
          active: true,
        },
      }
    end

    it "creates a template for admins" do
      sign_in admin

      expect do
        post admin_email_templates_path, params: valid_params, as: :json
      end.to change(EmailTemplate, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["success"]).to be(true)
    end

    it "returns validation errors" do
      sign_in admin

      post admin_email_templates_path,
           params: { email_template: valid_params[:email_template].merge(name: "", event_trigger: "") },
           as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["success"]).to be(false)
      expect(response.parsed_body["errors"]).to include(a_string_matching(/Name can't be blank/))
    end
  end

  describe "PATCH /admin/email_templates/:id" do
    it "updates the template for admins" do
      sign_in admin

      patch admin_email_template_path(template),
            params: { email_template: { subject: "Updated subject" } },
            as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["success"]).to be(true)
      expect(template.reload.subject).to eq("Updated subject")
    end

    it "returns validation errors when update fails" do
      sign_in admin

      patch admin_email_template_path(template),
            params: { email_template: { name: "" } },
            as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["success"]).to be(false)
      expect(response.parsed_body["errors"]).to include(a_string_matching(/Name can't be blank/))
    end
  end

  describe "DELETE /admin/email_templates/:id" do
    it "destroys the template for admins" do
      sign_in admin

      expect do
        delete admin_email_template_path(template), as: :json
      end.to change(EmailTemplate, :count).by(-1)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["success"]).to be(true)
    end
  end
end
