# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Workflow execution", type: :integration, aggregate_failures: true do
  let(:admin_user) { create(:user, :admin) }
  let(:approver) { create(:user, email: "approver@example.com") }
  let(:json_headers) do
    {
      "ACCEPT" => "application/json",
      "CONTENT_TYPE" => "application/json",
    }
  end

  before do
    sign_in admin_user
  end

  it "creates a workflow instance, approves it, and exposes notifications" do
    workflow = create(:workflow, status: "draft", trigger_type: "manual", name: "Integration Approval")
    create(
      :workflow_step,
      workflow: workflow,
      position: 1,
      node_type: "approval",
      assignee_type: "user",
      assignee_id: approver.id,
      logic: "any",
      title: "Approval Step"
    )
    workflow.update!(status: "active")
    asset = create(:asset, user: admin_user, status: :ready, title: "Workflow Asset")

    WorkflowInitiatorWorker.new.perform(asset.id, workflow.id)
    instance = WorkflowInstance.last
    expect(instance).to be_present

    get "/api/v1/workflow_instances"
    expect(response).to have_http_status(:ok)
    expect(json_body.fetch("instances").map { |row| row.fetch("id") }).to include(instance.id)

    sign_out admin_user
    sign_in approver

    get "/api/v1/workflows/dashboard"
    expect(response).to have_http_status(:ok)
    expect(json_body.fetch("my_tasks")).not_to be_empty
    task_id = json_body.fetch("my_tasks").first.fetch("task_id")

    post "/api/v1/workflow_tasks/#{task_id}/submit",
         params: { decision: "approved", comment: "Approved by integration test" }.to_json,
         headers: json_headers
    expect(response).to have_http_status(:ok)

    sign_out approver
    sign_in admin_user

    get "/api/v1/workflow_instances/#{instance.id}"
    expect(response).to have_http_status(:ok)
    expect(json_body.fetch("status")).to eq("completed")

    sign_out admin_user
    sign_in approver

    get "/api/v1/notifications"
    expect(response).to have_http_status(:ok)
    expect(json_body).not_to be_empty
  end
end
