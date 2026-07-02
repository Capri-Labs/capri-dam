# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::ImageProfiles coverage", type: :request do
  let(:user) { create(:user, admin: true) }

  before { sign_in user }

  def json = response.parsed_body

  it "lists only active profiles sorted by name and requires authentication" do
    create(:image_profile, name: "Zeta")
    create(:image_profile, name: "Alpha")
    create(:image_profile, :deleted, name: "Deleted")

    get "/api/v1/image_profiles", as: :json
    expect(response).to have_http_status(:ok)
    expect(json.map { |profile| profile["name"] }).to eq(%w[Alpha Zeta])

    sign_out user
    get "/api/v1/image_profiles", as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it "creates profiles from JSON crop payloads and falls back on invalid JSON" do
    post "/api/v1/image_profiles", params: {
      image_profile: {
        name: "Responsive",
        crop_type: "smart_crop",
        responsive_crop_enabled: true,
        responsive_crops: [ { name: "Large", width: 1200, height: 800 } ].to_json,
        unsharp_mask: { amount: 2, radius: 1, threshold: 3 },
      },
    }, as: :json
    expect(response).to have_http_status(:created)
    expect(json["responsive_crops"].first).to include("name" => "Large")

    post "/api/v1/image_profiles", params: {
      image_profile: { name: "Fallback", crop_type: "none", responsive_crops: "not-json" },
    }, as: :json
    expect(response).to have_http_status(:created)
    expect(json["responsive_crops"]).to eq([])
  end

  it "rejects invalid updates and missing profiles" do
    profile = create(:image_profile)

    patch "/api/v1/image_profiles/#{profile.id}", params: {
      image_profile: { name: "", crop_type: "invalid" },
    }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(json["errors"]).to be_present

    get "/api/v1/image_profiles/0", as: :json
    expect(response).to have_http_status(:not_found)
    expect(json).to eq("error" => "Image profile not found")
  end

  it "requires administrators for mutating actions" do
    sign_in create(:user, admin: false)

    post "/api/v1/image_profiles", params: {
      image_profile: { name: "Forbidden", crop_type: "none" },
    }, as: :json

    expect(response).to have_http_status(:forbidden)
    expect(json).to eq("error" => "Administrator privileges required.")
  end

  it "replaces, lists and removes folder assignments" do
    old_profile = create(:image_profile, name: "Old")
    new_profile = create(:image_profile, name: "New")
    folder = create(:folder, user: user, name: "Images")
    ImageProfileFolderAssignment.create!(image_profile: old_profile, folder_id: folder.id)

    post "/api/v1/image_profiles/#{new_profile.id}/apply_to_folder", params: { folder_id: folder.id }, as: :json
    expect(response).to have_http_status(:created)
    expect(ImageProfileFolderAssignment.where(folder_id: folder.id).pluck(:image_profile_id)).to eq([ new_profile.id ])

    get "/api/v1/image_profiles/#{new_profile.id}/folders", as: :json
    expect(response).to have_http_status(:ok)
    expect(json.first).to include("id" => folder.id, "name" => "Images")

    delete "/api/v1/image_profiles/#{new_profile.id}/remove_from_folder", as: :json
    expect(response).to have_http_status(:bad_request)

    delete "/api/v1/image_profiles/#{new_profile.id}/remove_from_folder", params: { folder_id: folder.id }, as: :json
    expect(response).to have_http_status(:no_content)
    expect(ImageProfileFolderAssignment.where(folder_id: folder.id)).to be_empty
  end

  it "soft deletes profiles" do
    profile = create(:image_profile)

    delete "/api/v1/image_profiles/#{profile.id}", as: :json

    expect(response).to have_http_status(:no_content)
    expect(profile.reload.deleted_at).to be_present
  end
end
