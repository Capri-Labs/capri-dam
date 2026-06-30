require 'rails_helper'

RSpec.describe "Api::Docs", type: :request do
  # ─────────────────────────────────────────
  # GET /api/rest
  # ─────────────────────────────────────────
  describe "GET /api/rest" do
    context "when accessed without authentication" do
      it "returns HTTP 200" do
        get "/api/rest"
        expect(response).to have_http_status(:ok)
      end

      it "returns HTML content-type" do
        get "/api/rest"
        expect(response.content_type).to include("text/html")
      end

      it "renders the Swagger UI widget" do
        get "/api/rest"
        expect(response.body).to include("swagger-ui-bundle.js")
      end

      it "points to the correct OpenAPI spec URL" do
        get "/api/rest"
        expect(response.body).to include("/api-docs/v1/swagger.yaml")
      end

      it "displays the nav link to the GraphQL docs" do
        get "/api/rest"
        expect(response.body).to include("/api/graphql")
      end
    end
  end

  # ─────────────────────────────────────────
  # GET /api/graphql
  # ─────────────────────────────────────────
  describe "GET /api/graphql" do
    context "when accessed without authentication" do
      it "returns HTTP 200" do
        get "/api/graphql"
        expect(response).to have_http_status(:ok)
      end

      it "returns HTML content-type" do
        get "/api/graphql"
        expect(response.content_type).to include("text/html")
      end

      it "contains the SpectaQL GraphQL documentation" do
        get "/api/graphql"
        expect(response.body).to include("GraphQL")
      end
    end
  end

  # ─────────────────────────────────────────
  # Legacy redirect — /docs/graphql
  # ─────────────────────────────────────────
  describe "GET /docs/graphql (legacy)" do
    it "redirects to /api/graphql" do
      get "/docs/graphql"
      expect(response).to redirect_to("/api/graphql")
    end

    it "returns a 301 permanent redirect" do
      get "/docs/graphql"
      expect(response).to have_http_status(:moved_permanently)
    end
  end

  # ─────────────────────────────────────────
  # Legacy redirect — /api_docs/index
  # ─────────────────────────────────────────
  describe "GET /api_docs/index (legacy)" do
    it "redirects to /api/rest" do
      get "/api_docs/index"
      expect(response).to redirect_to("/api/rest")
    end

    it "returns a 301 permanent redirect" do
      get "/api_docs/index"
      expect(response).to have_http_status(:moved_permanently)
    end
  end

  # ─────────────────────────────────────────
  # Legacy redirect — /developers/api
  # ─────────────────────────────────────────
  describe "GET /developers/api (legacy)" do
    it "redirects to /api/rest" do
      get "/developers/api"
      expect(response).to redirect_to("/api/rest")
    end

    it "returns a 301 permanent redirect" do
      get "/developers/api"
      expect(response).to have_http_status(:moved_permanently)
    end
  end
end
