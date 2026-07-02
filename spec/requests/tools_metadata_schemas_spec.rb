# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Tools::MetadataSchemas coverage", type: :request do
  let(:user) { create(:user) }

  it "renders the metadata schema shell for authenticated users" do
    sign_in user

    get "/tools/metadata_schemas"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-view="metadata-schemas-screen"')
  end

  it "returns 401 for unauthenticated HTML users" do
    get "/tools/metadata_schemas"

    expect(response).to have_http_status(:unauthorized)
  end

  it "returns 401 for unauthenticated JSON requests" do
    get "/tools/metadata_schemas", as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
