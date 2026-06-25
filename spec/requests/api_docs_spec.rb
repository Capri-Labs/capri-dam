require 'rails_helper'

# NOTE: The legacy /api_docs/index path now permanently redirects to /api/rest.
# Full documentation route specs live in spec/requests/api/docs_spec.rb.
RSpec.describe "ApiDocs (legacy routes)", type: :request do
  describe "GET /api_docs/index" do
    it "permanently redirects to /api/rest" do
      get "/api_docs/index"
      expect(response).to have_http_status(:moved_permanently)
      expect(response).to redirect_to("/api/rest")
    end
  end
end
