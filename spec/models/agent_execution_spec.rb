# frozen_string_literal: true

require "rails_helper"

RSpec.describe AgentExecution, type: :model do
  describe "validations" do
    subject { build(:agent_execution) }

    it { is_expected.to be_valid }

    it "requires a valid status" do
      subject.status = "bogus"
      expect(subject).not_to be_valid
    end

    it "requires a started_at" do
      subject.started_at = nil
      expect(subject).not_to be_valid
    end
  end

  describe "scopes" do
    let(:wf) { create(:agent_workflow) }

    it ".recent orders by started_at desc" do
      old = create(:agent_execution, agent_workflow: wf, started_at: 2.hours.ago)
      new_exec = create(:agent_execution, agent_workflow: wf, started_at: 1.minute.ago)
      expect(AgentExecution.recent.first).to eq(new_exec)
      expect(AgentExecution.recent.last).to eq(old)
    end

    it ".completed excludes running executions" do
      create(:agent_execution, :running, agent_workflow: wf)
      done = create(:agent_execution, agent_workflow: wf, status: "success")
      expect(AgentExecution.completed).to contain_exactly(done)
    end
  end
end
