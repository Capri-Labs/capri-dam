require "rails_helper"

RSpec.describe "Api::V1::AssetProvenanceRecords coverage", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:asset) { create(:asset) }

  before { sign_in admin }

  def json = response.parsed_body

  it "filters index results to AI-modified records" do
    create(:asset_provenance_record, :verified)
    matching = create(:asset_provenance_record, :ai_modified)

    get "/api/v1/asset_provenance_records", params: { ai_modified: "true" }, as: :json

    expect(response).to have_http_status(:ok)
    expect(json["records"].pluck("id")).to contain_exactly(matching.id)
  end

  it "rejects blank bulk_upsert payloads even with a valid gateway secret" do
    allow(Rails.application.credentials).to receive(:dig).with(:ai_gateway, :secret).and_return("test-secret")

    post "/api/v1/asset_provenance_records/bulk_upsert",
      params: { records: [] },
      headers: { "X-Gateway-Secret" => "test-secret" },
      as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(json).to eq("error" => "records array is required")
  end

  it "upserts valid rows, skips unresolved assets, and normalizes invalid statuses" do
    allow(Rails.application.credentials).to receive(:dig).with(:ai_gateway, :secret).and_return("test-secret")

    post "/api/v1/asset_provenance_records/bulk_upsert",
      params: {
        records: [
          { asset_id: "", manifest_status: "verified" },
          {
            asset_id: asset.uuid,
            manifest_status: "not-real",
            manifest_data: ActionController::Parameters.new(source: "gateway"),
          },
        ],
      },
      headers: { "X-Gateway-Secret" => "test-secret" },
      as: :json

    expect(response).to have_http_status(:ok)
    expect(json).to include("upserted" => 1, "skipped" => 1)

    record = AssetProvenanceRecord.find_by!(asset_id: asset.id)
    expect(record.manifest_status).to eq("unchecked")
    expect(record.manifest_data).to eq("source" => "gateway")
  end

  it "serializes nil asset fields when the association is unavailable" do
    record = create(:asset_provenance_record, :verified)
    allow_any_instance_of(AssetProvenanceRecord).to receive(:asset).and_return(nil) # rubocop:disable RSpec/AnyInstance

    get "/api/v1/asset_provenance_records/#{record.id}", as: :json

    expect(response).to have_http_status(:ok)
    expect(json).to include("asset_uuid" => nil, "asset_title" => nil)
  end
end
