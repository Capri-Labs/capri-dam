# frozen_string_literal: true

require "rails_helper"

RSpec.describe FixityAuditWorker do
  let(:asset) { create(:asset) }

  def verifiable_version
    create(
      :asset_version,
      asset: asset,
      properties: { "checksum_sha256" => Digest::SHA256.hexdigest(SecureRandom.hex), "storage_path" => "a/#{SecureRandom.uuid}" },
    )
  end

  def result(status)
    Fixity::Verifier::Result.new(status: status, check: nil, message: nil)
  end

  it "tallies each verdict it reaches" do
    verifiable_version
    verifiable_version
    allow(Fixity::Verifier).to receive(:call).and_return(result("passed"))

    expect(described_class.new.perform).to eq("passed" => 2)
  end

  it "keeps going when one version blows up, because the batch is the day's coverage" do
    verifiable_version
    verifiable_version
    call_count = 0
    allow(Fixity::Verifier).to receive(:call) do
      call_count += 1
      raise Errno::ECONNREFUSED if call_count == 1

      result("passed")
    end

    tally = described_class.new.perform

    expect(tally["error"]).to eq(1)
    expect(tally["passed"]).to eq(1)
  end

  it "respects the budget it is given" do
    3.times { verifiable_version }
    allow(Fixity::Verifier).to receive(:call).and_return(result("passed"))

    described_class.new.perform(2)

    expect(Fixity::Verifier).to have_received(:call).twice
  end

  it "ignores versions that carry no digest" do
    create(:asset_version, asset: asset, properties: { "storage_path" => "a/b" })
    allow(Fixity::Verifier).to receive(:call)

    expect(described_class.new.perform).to eq({})
    expect(Fixity::Verifier).not_to have_received(:call)
  end

  describe "alerting" do
    let!(:admin_group) { UserGroup.find_or_create_by!(slug: "administrators") { |g| g.name = "Administrators" } }
    let!(:admin) { create(:user).tap { |u| u.user_groups << admin_group } }

    before { verifiable_version }

    it "notifies administrators once per run, not once per asset" do
      verifiable_version
      allow(Fixity::Verifier).to receive(:call).and_return(result("failed"))

      expect { described_class.new.perform }.to change { InboxMessage.where(recipient: admin).count }.by(1)

      message = InboxMessage.where(recipient: admin).last
      expect(message.message_type).to eq("system")
      expect(message.subject).to include("2 integrity issues")
    end

    it "treats a missing object as an incident" do
      allow(Fixity::Verifier).to receive(:call).and_return(result("missing"))

      expect { described_class.new.perform }.to change(InboxMessage, :count).by(1)
    end

    it "stays silent about an inconclusive read" do
      allow(Fixity::Verifier).to receive(:call).and_return(result("unreadable"))

      expect { described_class.new.perform }.not_to change(InboxMessage, :count)
    end

    it "stays silent when everything passes" do
      allow(Fixity::Verifier).to receive(:call).and_return(result("passed"))

      expect { described_class.new.perform }.not_to change(InboxMessage, :count)
    end
  end
end
