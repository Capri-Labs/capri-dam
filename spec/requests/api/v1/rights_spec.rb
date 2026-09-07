require "rails_helper"

RSpec.describe "Api::V1::Rights", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "GET /api/v1/rights/usage_terms" do
    it "returns the controlled vocabulary with labels and distribution flags" do
      get "/api/v1/rights/usage_terms"

      expect(response).to have_http_status(:ok)
      body = response.parsed_body

      expect(body["usage_terms"].map { |t| t["code"] })
        .to match_array(Rights::UsageTerms::CODES)
      expect(body["default"]).to eq(Rights::UsageTerms::DEFAULT)
    end

    it "marks internal_only as not externally distributable" do
      # This flag drives the UI warning, so it has to match what
      # Rights::DownloadPolicy actually enforces rather than being a separate
      # opinion about the same term.
      get "/api/v1/rights/usage_terms"

      internal = response.parsed_body["usage_terms"].find { |t| t["code"] == "internal_only" }
      expect(internal["external"]).to be(false)
      expect(internal["label"]).to eq("Internal Use Only")

      expect(Rights::UsageTerms.externally_distributable?("internal_only")).to be(false)
    end

    it "agrees with Rights::UsageTerms for every term" do
      get "/api/v1/rights/usage_terms"

      response.parsed_body["usage_terms"].each do |term|
        expect(term["external"])
          .to eq(Rights::UsageTerms.externally_distributable?(term["code"])),
              "#{term["code"]} disagreed with the policy vocabulary"
      end
    end

    it "requires authentication" do
      sign_out user

      get "/api/v1/rights/usage_terms"

      expect(response).not_to have_http_status(:ok)
    end
  end
end
