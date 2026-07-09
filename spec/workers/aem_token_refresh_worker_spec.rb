require "rails_helper"

RSpec.describe AemTokenRefreshWorker, type: :worker do
  it "refreshes a connector with no cached token and leaves a valid one untouched" do
    stale = create(:system_connector, :jwt_service_account)
    fresh = create(:system_connector, :jwt_service_account, access_token: "cached", access_token_expires_at: 1.hour.from_now)

    allow(Ims::JwtTokenExchangeService).to receive(:new).with(stale).and_return(
      instance_double(Ims::JwtTokenExchangeService, call: { access_token: "new-token", expires_at: 1.hour.from_now })
    )
    expect(Ims::JwtTokenExchangeService).not_to receive(:new).with(fresh)

    described_class.new.perform

    expect(stale.reload.access_token).to eq("new-token")
    expect(fresh.reload.access_token).to eq("cached")
  end

  it "logs and continues when a single connector's refresh fails" do
    failing = create(:system_connector, :jwt_service_account)
    ok = create(:system_connector, :jwt_service_account)

    allow(Ims::JwtTokenExchangeService).to receive(:new).with(failing).and_raise(Ims::JwtTokenExchangeService::Error, "boom")
    allow(Ims::JwtTokenExchangeService).to receive(:new).with(ok).and_return(
      instance_double(Ims::JwtTokenExchangeService, call: { access_token: "ok-token", expires_at: 1.hour.from_now })
    )

    expect { described_class.new.perform }.not_to raise_error

    expect(failing.reload.token_status).to eq("error")
    expect(ok.reload.access_token).to eq("ok-token")
  end

  it "ignores token-type (non-JWT) connectors" do
    token_connector = create(:system_connector)
    expect(Ims::JwtTokenExchangeService).not_to receive(:new)

    described_class.new.perform

    expect(token_connector.reload.token_status).to eq("not_configured")
  end
end
