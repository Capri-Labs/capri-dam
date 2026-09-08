require 'rails_helper'

RSpec.describe AiAutoTagWorker do
  let(:asset) { create(:asset) }
  let(:run)   { create(:ai_tagging_run, asset: asset, status: 'queued') }

  def redis_double
    instance_double(Redis).tap { |r| allow(r).to receive(:publish) }
  end

  it 'marks the run running and publishes one dispatch event' do
    conn = redis_double
    allow(Sidekiq).to receive(:redis).and_yield(conn)

    described_class.new.perform(run.id)

    expect(run.reload.status).to eq('running')
    expect(conn).to have_received(:publish).with('ai_gateway_events', anything).once
  end

  it 'sends the allow-listed capability and the callback url' do
    conn = redis_double
    allow(Sidekiq).to receive(:redis).and_yield(conn)

    described_class.new.perform(run.id)

    payload = nil
    expect(conn).to have_received(:publish) { |_channel, json| payload = JSON.parse(json) }

    expect(payload['event']).to eq('ai_tagging.dispatch')
    expect(payload['capability']).to eq('vision.tag')
    expect(payload['run_id']).to eq(run.id)
    expect(payload['callback_url']).to include("/api/v1/ai_tagging_runs/#{run.id}/suggestions")
    # Told to the gateway so it can stop early — but re-applied on import.
    expect(payload['min_confidence']).to eq(AiTaggingRun::MIN_CONFIDENCE)
    expect(payload['max_suggestions']).to eq(AiTaggingRun::MAX_SUGGESTIONS)
  end

  # A Sidekiq retry must not dispatch the same run twice and double every label.
  it 'no-ops for a run that is no longer queued' do
    conn = redis_double
    allow(Sidekiq).to receive(:redis).and_yield(conn)
    run.update!(status: 'running')

    described_class.new.perform(run.id)

    expect(conn).not_to have_received(:publish)
  end

  it 'no-ops for a run that no longer exists' do
    expect { described_class.new.perform(SecureRandom.uuid) }.not_to raise_error
  end

  # A gateway that is down should leave the run visibly failed rather than
  # stuck in running forever, where a curator waits for suggestions that are
  # never coming.
  it 'marks the run failed when dispatch raises' do
    allow(Sidekiq).to receive(:redis).and_raise(StandardError, 'redis down')

    described_class.new.perform(run.id)

    expect(run.reload.status).to eq('failed')
    expect(run.error_message).to match(/redis down/)
  end
end
