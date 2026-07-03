# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::UpdateBinRetentionPolicy, type: :request do
  subject(:mutation) do
    described_class.allocate.tap do |instance|
      allow(instance).to receive(:context).and_return(context)
    end
  end

  let(:admin) { create(:user, :admin) }
  let(:viewer) { create(:user) }
  let(:context) { { current_user: admin } }

  before do
    Setting.set("bin_retention_days", nil)
    Setting.set("bin_workflow_behavior", nil)
    Setting.set("bin_purge_batch_size", nil)
    Setting.set("bin_purge_notify_admins", nil)
  end

  it "requires authentication" do
    unauthenticated = described_class.allocate.tap do |instance|
      allow(instance).to receive(:context).and_return({})
    end

    expect(unauthenticated.resolve(retention_days: 7)).to eq(
      policy: nil,
      errors: [ "Authentication required." ],
    )
  end

  it "rejects non-admin users" do
    result = described_class.allocate.tap { |instance| allow(instance).to receive(:context).and_return(current_user: viewer) }
                             .resolve(retention_days: 7)

    expect(result).to eq(policy: nil, errors: [ "Administrator privileges required." ])
  end

  it "updates only the provided settings and falls back to defaults for omitted values" do
    result = mutation.resolve(retention_days: 7)

    expect(result[:errors]).to eq([])
    expect(Setting.get("bin_retention_days").to_i).to eq(7)
    expect(Setting.get("bin_workflow_behavior")).to be_nil
    expect(Setting.get("bin_purge_batch_size")).to be_nil
    expect(result[:policy]).to include(
      retention_days: 7,
      workflow_behavior: BinPurgeWorker::DEFAULT_WORKFLOW_BEHAVIOR,
      batch_size: BinPurgeWorker::DEFAULT_BATCH_SIZE,
      notify_admins: BinPurgeWorker::DEFAULT_NOTIFY_ADMINS,
    )
  end
end
