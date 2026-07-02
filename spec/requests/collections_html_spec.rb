# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Collections HTML coverage", type: :request do
  let(:user) { create(:user) }
  before { sign_in user }

  it "renders the collections shell for base and wildcard paths" do
    get "/collections"
    expect(response).to have_http_status(:ok)
    expect(assigns(:active_view)).to eq("Collections")

    get "/collections/nested/workspace"
    expect(response).to have_http_status(:ok)
    expect(assigns(:active_view)).to eq("Collections")
  end
end
