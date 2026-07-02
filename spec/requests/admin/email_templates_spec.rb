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

# ---- merged from email_templates_coverage_spec.rb ----
RSpec.describe "Admin::EmailTemplates coverage additions", type: :request do
  let(:admin) { create(:user, :admin) }

  before do
    sign_in admin
    allow(EmailDispatcherWorker).to receive(:perform_async)
  end

  describe "GET /admin/email_templates" do
    it "renders the HTML shell" do
      get "/admin/email_templates"
      expect(response).to have_http_status(:ok)
    end

    it "returns an empty JSON list" do
      get "/admin/email_templates", as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["email_templates"]).to eq([])
    end
  end

  describe "event triggers" do
    it "returns all supported system events" do
      get "/admin/email_templates/event_triggers", as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["events"].map { |event| event["id"] }).to include("user_created", "report_ready")
    end
  end

  describe "create/update details" do
    it "creates templates with variables, preview data, category, and creator" do
      post "/admin/email_templates", params: {
        email_template: {
          name: "Report Ready",
          event_trigger: "report_ready_custom",
          subject: "Report {{report.name}}",
          html_body: "<p>Ready</p>",
          text_body: "Ready",
          active: false,
          description: "Report notification",
          category: "system",
          variables: { report: [ "name" ] },
          preview_data: { report: { name: "Weekly" } },
        },
      }, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body["email_template"]
      expect(body).to include("active" => false, "category" => "system", "created_by_id" => admin.id)
      expect(body["preview_data"]).to include("report")
    end

    it "returns validation errors for invalid category" do
      post "/admin/email_templates", params: {
        email_template: { name: "Bad", event_trigger: "bad_event", subject: "Bad", category: "invalid" },
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["success"]).to be(false)
      expect(response.parsed_body["errors"]).to include(a_string_matching(/Category/))
    end
  end

  describe "send_test" do
    it "queues a test delivery with explicit recipient and payload" do
      template = create(:email_template, event_trigger: "test_payload")

      expect do
        post "/admin/email_templates/#{template.id}/send_test", params: {
          recipient_email: "qa@example.com", payload: { user: { first_name: "QA" } }
        }, as: :json
      end.to change(EmailDelivery, :count).by(1)

      delivery = EmailDelivery.last
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["delivery_id"]).to eq(delivery.id)
      expect(delivery).to have_attributes(recipient_email: "qa@example.com", status: "pending")
      expect(delivery.payload).to include("user" => { "first_name" => "QA" })
      expect(EmailDispatcherWorker).to have_received(:perform_async).with(delivery.id)
    end

    it "falls back to preview data and current user email" do
      template = create(:email_template, event_trigger: "preview_payload", preview_data: { "asset" => { "name" => "Hero" } })

      post "/admin/email_templates/#{template.id}/send_test", as: :json

      expect(response).to have_http_status(:ok)
      delivery = EmailDelivery.last
      expect(delivery.recipient_email).to eq(admin.email)
      expect(delivery.payload).to include("asset" => { "name" => "Hero" })
    end
  end

  describe "destroy failure" do
    it "returns an error when destroy fails" do
      template = create(:email_template, event_trigger: "destroy_failure")
      allow_any_instance_of(EmailTemplate).to receive(:destroy).and_return(false)

      delete "/admin/email_templates/#{template.id}", as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("success" => false)
    end
  end
end
