# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::VideoProfiles coverage", type: :request do
  let(:user) { create(:user, admin: true) }

  before { sign_in user }

  def json = response.parsed_body

  it "lists active profiles and shows presets and assigned folders" do
    create(:video_profile, name: "Zeta")
    profile = create(:video_profile, :with_adaptive_presets, name: "Alpha")
    create(:video_profile, :deleted, name: "Deleted")
    folder = create(:folder, user: user, name: "Videos")
    VideoProfileFolderAssignment.create!(video_profile: profile, folder_id: folder.id)

    get "/api/v1/video_profiles", as: :json
    expect(response).to have_http_status(:ok)
    expect(json.map { |profile_json| profile_json["name"] }).to eq(%w[Alpha Zeta])

    get "/api/v1/video_profiles/#{profile.id}", as: :json
    expect(response).to have_http_status(:ok)
    expect(json["encoding_presets"].size).to eq(3)
    expect(json["folders"].first).to include("id" => folder.id, "name" => "Videos")
  end

  it "creates profiles from JSON smart crop ratios and handles invalid JSON" do
    post "/api/v1/video_profiles", params: {
      video_profile: {
        name: "Adaptive",
        smart_crop_ratios: [ { name: "16:9", crop_ratio: "16:9" } ].to_json,
        encoding_presets_attributes: [
          { name: "720p", height: 720, video_bitrate_kbps: 3000, frame_rate_fps: 30, audio_codec: "he_aac", audio_bitrate_kbps: 128 },
        ],
      },
    }, as: :json
    expect(response).to have_http_status(:created)
    expect(json["smart_crop_ratios"].first).to include("name" => "16:9")
    expect(json["encoding_presets"].first).to include("size_label" => "auto x 720")

    post "/api/v1/video_profiles", params: {
      video_profile: { name: "Fallback", smart_crop_ratios: "not-json" },
    }, as: :json
    expect(response).to have_http_status(:created)
    expect(json["smart_crop_ratios"]).to eq([])
  end

  it "parses preset advanced_params JSON strings and falls back to an empty hash" do
    post "/api/v1/video_profiles", params: {
      video_profile: {
        name: "Advanced Params",
        encoding_presets_attributes: [
          {
            name: "Valid",
            height: 720,
            video_bitrate_kbps: 3000,
            advanced_params: { h264Level: "41" }.to_json,
          },
          {
            name: "Invalid",
            height: 360,
            video_bitrate_kbps: 900,
            advanced_params: "{bad-json",
          },
        ],
      },
    }, as: :json

    expect(response).to have_http_status(:created)
    expect(json["encoding_presets"].find { |preset| preset["name"] == "Valid" }["advanced_params"]).to eq("h264Level" => "41")
    expect(json["encoding_presets"].find { |preset| preset["name"] == "Invalid" }["advanced_params"]).to eq({})
  end

  it "rejects invalid updates and missing profiles" do
    profile = create(:video_profile)

    patch "/api/v1/video_profiles/#{profile.id}", params: {
      video_profile: { name: "", smart_crop_ratios: [ { name: "" } ].to_json },
    }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(json["errors"]).to be_present

    get "/api/v1/video_profiles/0", as: :json
    expect(response).to have_http_status(:not_found)
    expect(json).to eq("error" => "Video profile not found")
  end

  it "requires administrators for mutating actions" do
    sign_in create(:user, admin: false)

    post "/api/v1/video_profiles", params: {
      video_profile: { name: "Forbidden" },
    }, as: :json

    expect(response).to have_http_status(:forbidden)
    expect(json).to eq("error" => "Administrator privileges required.")
  end

  it "copies profiles with presets" do
    profile = create(:video_profile, :with_adaptive_presets, name: "Original")

    post "/api/v1/video_profiles/#{profile.id}/copy", params: { name: "Clone" }, as: :json

    expect(response).to have_http_status(:created)
    expect(json).to include("name" => "Clone")
    expect(json["encoding_presets"].size).to eq(3)
  end

  it "returns validation errors when copying fails" do
    profile = create(:video_profile, :with_adaptive_presets)
    allow_any_instance_of(VideoProfile).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(profile))

    post "/api/v1/video_profiles/#{profile.id}/copy", params: { name: "Broken copy" }, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(json["errors"]).to be_present
  end

  it "replaces, lists and removes folder assignments" do
    old_profile = create(:video_profile, name: "Old")
    new_profile = create(:video_profile, name: "New")
    folder = create(:folder, user: user, name: "Videos")
    VideoProfileFolderAssignment.create!(video_profile: old_profile, folder_id: folder.id)

    post "/api/v1/video_profiles/#{new_profile.id}/apply_to_folder", params: { folder_id: folder.id }, as: :json
    expect(response).to have_http_status(:created)
    expect(VideoProfileFolderAssignment.where(folder_id: folder.id).pluck(:video_profile_id)).to eq([ new_profile.id ])

    get "/api/v1/video_profiles/#{new_profile.id}/folders", as: :json
    expect(response).to have_http_status(:ok)
    expect(json.first).to include("id" => folder.id, "name" => "Videos")

    delete "/api/v1/video_profiles/#{new_profile.id}/remove_from_folder", as: :json
    expect(response).to have_http_status(:bad_request)

    delete "/api/v1/video_profiles/#{new_profile.id}/remove_from_folder", params: { folder_id: folder.id }, as: :json
    expect(response).to have_http_status(:no_content)
    expect(VideoProfileFolderAssignment.where(folder_id: folder.id)).to be_empty
  end

  it "returns validation errors when assigning a folder fails" do
    profile = create(:video_profile, name: "Broken")
    folder = create(:folder, user: user, name: "Videos")
    assignment = VideoProfileFolderAssignment.new(video_profile: profile, folder_id: folder.id)
    assignment.errors.add(:folder_id, "is invalid")
    allow(VideoProfileFolderAssignment).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(assignment))

    post "/api/v1/video_profiles/#{profile.id}/apply_to_folder", params: { folder_id: folder.id }, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(json["error"]).to include("Folder")
  end

  it "soft deletes profiles" do
    profile = create(:video_profile)

    delete "/api/v1/video_profiles/#{profile.id}", as: :json

    expect(response).to have_http_status(:no_content)
    expect(profile.reload.deleted_at).to be_present
  end
end
