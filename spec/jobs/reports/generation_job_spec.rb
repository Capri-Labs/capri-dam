require "rails_helper"

RSpec.describe Reports::GenerationJob, type: :job do
  it "delegates snapshot generation to the reports orchestrator" do
    allow(Reports::Orchestrator).to receive(:execute!)

    described_class.perform_now(123)

    expect(Reports::Orchestrator).to have_received(:execute!).with(123)
  end

  it "lets ActiveJob retry configured errors by reraising" do
    allow(Reports::Orchestrator).to receive(:execute!).and_raise(StandardError, "deadlock")

    expect { described_class.perform_now(123) }.to raise_error(RuntimeError, /Couldn't determine a delay/)
  end
end
