# frozen_string_literal: true

require "rails_helper"

# GraphQL read access for AI Batch Jobs (admin-only).
RSpec.describe "GraphQL aiBatchJobs", type: :request do
  let(:admin)  { create(:user, :admin) }
  let(:viewer) { create(:user) }

  def gql_post(query:, user:)
    sign_in(user)
    post "/graphql", params: { query: query }.to_json,
                     headers: { "Content-Type" => "application/json", "Accept" => "application/json" }
    JSON.parse(response.body)
  end

  let(:list_query) do
    <<~GQL
      { aiBatchJobs { id taskType status progressPercent } }
    GQL
  end

  it "returns jobs for an admin" do
    create(:ai_batch_job, :running)
    body = gql_post(query: list_query, user: admin)
    expect(body["errors"]).to be_nil
    expect(body.dig("data", "aiBatchJobs").size).to eq(1)
    expect(body.dig("data", "aiBatchJobs", 0, "progressPercent")).to be_a(Integer)
  end

  it "returns an empty list for a non-admin" do
    create(:ai_batch_job)
    body = gql_post(query: list_query, user: viewer)
    expect(body.dig("data", "aiBatchJobs")).to eq([])
  end

  it "fetches a single job by id for an admin" do
    job   = create(:ai_batch_job, :completed)
    query = "{ aiBatchJob(id: #{job.id}) { id status taskLabel } }"
    body  = gql_post(query: query, user: admin)
    expect(body.dig("data", "aiBatchJob", "status")).to eq("completed")
    expect(body.dig("data", "aiBatchJob", "taskLabel")).to eq("Metadata Extraction")
  end

  it "exposes createdBy when present and returns nil when the task descriptor is unavailable" do
    present_job = create(:ai_batch_job, created_by: admin)
    missing_descriptor_job = create(:ai_batch_job, created_by: nil)
    allow_any_instance_of(AiBatchJob).to receive(:task_descriptor) do |job|
      job.id == missing_descriptor_job.id ? nil : Ai::BatchTaskRegistry.task(job.task_type)
    end

    query = <<~GQL
      {
        present: aiBatchJob(id: #{present_job.id}) { createdBy taskLabel }
        missing: aiBatchJob(id: #{missing_descriptor_job.id}) { createdBy taskLabel }
      }
    GQL
    body = gql_post(query: query, user: admin)

    expect(body.dig("data", "present", "createdBy")).to eq(admin.email)
    expect(body.dig("data", "missing", "createdBy")).to be_nil
    expect(body.dig("data", "missing", "taskLabel")).to be_nil
  end

  it "rejects type access for non-admin and anonymous contexts" do
    job = create(:ai_batch_job)

    expect(Types::AiBatchJobType.authorized?(job, { current_user: admin })).to be(true)
    expect(Types::AiBatchJobType.authorized?(job, { current_user: viewer })).to be(false)
    expect(Types::AiBatchJobType.authorized?(job, {})).to be_nil
  end
end
