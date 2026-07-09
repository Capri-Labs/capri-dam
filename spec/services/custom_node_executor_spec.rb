require "rails_helper"

RSpec.describe CustomNodeExecutor do
  let(:user) { create(:user) }
  let(:asset) { create(:asset, user: user, status: "in_review", properties: { "tags" => [ "old" ], "format" => "jpg" }) }
  let(:workflow) { create(:workflow) }
  let(:instance) { create(:workflow_instance, asset: asset, workflow: workflow, status: "in_progress") }
  let(:step) do
    create(
      :workflow_step,
      workflow: workflow,
      step_type: "automated_action",
      node_type: "plugin:acme_watermark",
      assignee_type: "system",
      assignee_id: 0,
      step_config: { "quality" => "high", "secret" => "step-secret" },
      title: "Watermark",
    )
  end
  let(:endpoint) { "https://plugins.example.com/workflow/custom-node" }
  let!(:definition) do
    create(
      :custom_node_definition,
      key: "acme_watermark",
      runtime: { "endpoint_url" => endpoint, "timeout_ms" => 5000, "secret" => "shared-secret" },
    )
  end

  before do
    allow(Resolv).to receive(:getaddresses).with("plugins.example.com").and_return([ "203.0.113.10" ])
  end

  it "applies whitelisted actions and returns the requested branch" do
    request = stub_request(:post, endpoint)
      .with(headers: { "X-Capri-Signature" => /\A[0-9a-f]{64}\z/ }) do |req|
        body = JSON.parse(req.body)
        expect(body["event"]).to eq("workflow.custom_node")
        expect(body["node_key"]).to eq("acme_watermark")
        expect(body["config"]).to eq("quality" => "high")
      end
      .to_return(
        status: 200,
        body: {
          set_tags: [ "hero" ],
          add_tags: [ "campaign" ],
          remove_tags: [ "old" ],
          patch_metadata: { "reviewed_by_plugin" => true },
          set_status: "approved",
          branch: "approved_path",
          ignored: "not applied",
        }.to_json,
        headers: { "Content-Type" => "application/json" },
      )

    result = described_class.new(instance, step, step.step_config.with_indifferent_access).call

    expect(request).to have_been_requested
    expect(result).to eq([ :branch, "approved_path" ])
    expect(asset.reload.properties).to include("tags" => [ "hero", "campaign" ], "reviewed_by_plugin" => true)
    expect(asset.status).to eq("approved")
    expect(definition.reload.failure_count).to eq(0)
    expect(definition.last_dispatched_at).to be_present
  end

  it "returns nil for linear plugin responses" do
    stub_request(:post, endpoint).to_return(status: 200, body: { add_tags: [ "linear" ] }.to_json)

    expect(described_class.new(instance, step, step.step_config).call).to be_nil
    expect(asset.reload.properties["tags"]).to include("linear")
  end

  it "increments failures and disables at the circuit breaker threshold" do
    definition.update!(failure_count: CustomNodeDefinition::CIRCUIT_BREAKER_THRESHOLD - 1)
    stub_request(:post, endpoint).to_return(status: 503, body: "unavailable")

    expect(described_class.new(instance, step, step.step_config).call).to be_nil
    expect(definition.reload.failure_count).to eq(CustomNodeDefinition::CIRCUIT_BREAKER_THRESHOLD)
    expect(definition).to be_disabled
    expect(definition.last_error).to eq("HTTP 503")
  end

  it "rejects endpoints resolving to private addresses" do
    definition.update!(runtime: definition.runtime.merge("endpoint_url" => "https://private.example.com/plugin"))
    allow(Resolv).to receive(:getaddresses).with("private.example.com").and_return([ "127.0.0.1" ])

    expect(described_class.new(instance, step, step.step_config).call).to be_nil
    expect(definition.reload.failure_count).to eq(1)
    expect(definition.last_error).to include("private address")
  end

  it "no-ops when the definition is missing" do
    definition.destroy!

    expect(described_class.new(instance, step, step.step_config).call).to be_nil
    expect(asset.reload.properties["tags"]).to eq([ "old" ])
  end

  it "no-ops when the definition is disabled" do
    definition.update!(status: "disabled")

    expect(described_class.new(instance, step, step.step_config).call).to be_nil
    expect(asset.reload.properties["tags"]).to eq([ "old" ])
  end

  it "no-ops when the circuit is open" do
    definition.update!(failure_count: CustomNodeDefinition::CIRCUIT_BREAKER_THRESHOLD)

    expect(described_class.new(instance, step, step.step_config).call).to be_nil
    expect(asset.reload.properties["tags"]).to eq([ "old" ])
  end
end
