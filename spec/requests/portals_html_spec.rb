# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Portals HTML shell", type: :request do
  let(:user) { create(:user) }

  it "renders the management shell for a signed-in user" do
    sign_in user

    get "/portals"

    expect(response).to have_http_status(:ok)
    expect(assigns(:active_view)).to eq("Portals")
    expect(response.body).to include('data-view="portalsView"')
  end

  # The screen lists who has been sent what outside the organisation, so it is
  # not a page an anonymous visitor may reach — even though the data itself is
  # served separately by the API.
  it "redirects an anonymous visitor to sign in" do
    get "/portals"

    expect(response).to have_http_status(:found)
    expect(response).to redirect_to(new_user_session_path)
  end
end
