# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard HTML coverage", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  it "renders dashboard with and without search results" do
    create(:asset, user: user, title: "Hero Asset", properties: { "original_filename" => "hero.jpg", "mime_type" => "image/jpeg", "size_human" => "1 KB" })

    get "/dashboard"
    expect(response).to have_http_status(:ok)
    expect(assigns(:active_view)).to eq("Overview")
    expect(assigns(:assets_json)).to include("Hero Asset")

    get "/dashboard", params: { search: "missing" }
    expect(response).to have_http_status(:ok)
    expect(assigns(:search_term)).to eq("missing")
    expect(assigns(:assets_json)).to eq("[]")
  end

  it "falls back to unknown metadata labels when asset properties are missing" do
    relation = instance_double(ActiveRecord::Relation)
    asset = instance_double(Asset, id: 1, uuid: "asset-1", title: nil, properties: nil)
    allow(Asset).to receive(:active).and_return(relation)
    allow(relation).to receive(:limit).with(20).and_return([ asset ])

    get "/dashboard"

    expect(response).to have_http_status(:ok)
    expect(assigns(:assets_json)).to include("Untitled Asset", "Unknown", "0 KB")
  end

  it "renders all dashboard shells and records view state" do
    get "/bin"
    expect(response).to have_http_status(:ok)
    expect(assigns(:active_view)).to eq("Bin")

    get "/folders"
    expect(response).to have_http_status(:ok)
    expect(assigns(:active_view)).to eq("All Assets")

    get "/assets", params: { id: "asset-uuid" }
    expect(response).to have_http_status(:ok)
    expect(assigns(:asset_id)).to eq("asset-uuid")

    get "/duplicates"
    expect(response).to have_http_status(:ok)
    expect(assigns(:active_view)).to eq("Duplicate Manager")

    get "/search"
    expect(response).to have_http_status(:ok)
    expect(assigns(:active_view)).to eq("Search")

    get "/inbox"
    expect(response).to have_http_status(:ok)
    expect(assigns(:active_view)).to eq("Inbox")
  end

  it "redirects unauthenticated users" do
    sign_out user
    get "/dashboard"
    expect(response).to have_http_status(:found)
  end
end
