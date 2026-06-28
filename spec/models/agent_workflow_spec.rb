# frozen_string_literal: true

require "rails_helper"

RSpec.describe AgentWorkflow, type: :model do
  describe "validations" do
    subject { build(:agent_workflow) }

    it { is_expected.to be_valid }

    it "requires a name" do
      subject.name = ""
      expect(subject).not_to be_valid
      expect(subject.errors[:name]).to be_present
    end

    it "rejects an unknown trigger_event" do
      subject.trigger_event = "not.a.real.event"
      expect(subject).not_to be_valid
    end

    it "accepts every whitelisted trigger_event" do
      AgentWorkflow::TRIGGER_EVENTS.each do |ev|
        subject.trigger_event = ev
        expect(subject).to be_valid, "expected #{ev} to be valid"
      end
    end

    it "requires an agent_model" do
      subject.agent_model = ""
      expect(subject).not_to be_valid
    end
  end

  describe "associations" do
    it "destroys dependent executions" do
      wf = create(:agent_workflow)
      create_list(:agent_execution, 2, agent_workflow: wf)
      expect { wf.destroy }.to change(AgentExecution, :count).by(-2)
    end
  end

  describe "scopes" do
    it ".active_only returns only active workflows" do
      active = create(:agent_workflow, :active)
      create(:agent_workflow, active: false)
      expect(AgentWorkflow.active_only).to contain_exactly(active)
    end
  end

  describe "#reliability" do
    let(:wf) { create(:agent_workflow) }

    it "returns nil when there are no executions" do
      expect(wf.reliability).to be_nil
    end

    it "computes the success percentage of recent runs" do
      create_list(:agent_execution, 3, agent_workflow: wf, status: "success")
      create(:agent_execution, agent_workflow: wf, status: "failed")
      expect(wf.reliability).to eq(75.0)
    end
  end

  describe "#avg_duration_ms" do
    let(:wf) { create(:agent_workflow) }

    it "returns nil with no completed executions" do
      expect(wf.avg_duration_ms).to be_nil
    end

    it "averages duration_ms across executions" do
      create(:agent_execution, agent_workflow: wf, duration_ms: 1000)
      create(:agent_execution, agent_workflow: wf, duration_ms: 2000)
      expect(wf.avg_duration_ms).to eq(1500)
    end
  end

  describe "#to_gateway_payload" do
    it "emits an activated event when active" do
      wf = build(:agent_workflow, :active)
      expect(wf.to_gateway_payload[:event]).to eq("agent_workflow.activated")
    end

    it "emits a deactivated event when inactive" do
      wf = build(:agent_workflow, active: false)
      expect(wf.to_gateway_payload[:event]).to eq("agent_workflow.deactivated")
    end
  end

  describe "gateway broadcast" do
    it "does not raise when Redis is unavailable" do
      allow(Sidekiq).to receive(:redis).and_raise(StandardError.new("redis down"))
      expect { create(:agent_workflow) }.not_to raise_error
    end
  end
end
