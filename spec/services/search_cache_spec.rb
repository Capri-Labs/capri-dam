# frozen_string_literal: true

require "rails_helper"

RSpec.describe SearchCache, type: :service do
  before do
    # SearchCache.fetch short-circuits to an uncached yield in the test
    # environment (mirrors config.cache_store = :null_store) so we stub
    # Rails.env.test? to false to exercise the real Redis-backed code path.
    allow(Rails.env).to receive(:test?).and_return(false)
    described_class.instance_variable_set(:@redis, nil)
  end

  after { described_class.instance_variable_set(:@redis, nil) }

  describe ".fetch" do
    it "computes and stores the block result on a cache miss" do
      fake_redis = instance_double(Redis)
      store = {}
      allow(fake_redis).to receive(:get) { |key| store[key] }
      allow(fake_redis).to receive(:setex) { |key, _ttl, value| store[key] = value }
      allow(Redis).to receive(:new).and_return(fake_redis)

      result = described_class.fetch("widgets", expires_in: 60) { { hello: "world" } }

      expect(result).to eq(hello: "world")
      expect(store["dam:search:widgets"]).to eq({ hello: "world" }.to_json)
    end

    it "returns the cached value without re-invoking the block on a hit" do
      fake_redis = instance_double(Redis)
      allow(fake_redis).to receive(:get).and_return({ cached: true }.to_json)
      allow(Redis).to receive(:new).and_return(fake_redis)

      generator = instance_double(Proc, call: { cached: false })

      result = described_class.fetch("widgets") { generator.call }

      expect(result).to eq(cached: true)
      expect(generator).not_to have_received(:call)
    end

    it "falls back to an uncached value when Redis raises a connection error" do
      fake_redis = instance_double(Redis)
      allow(fake_redis).to receive(:get).and_raise(Redis::CannotConnectError)
      allow(Redis).to receive(:new).and_return(fake_redis)
      allow(Rails.logger).to receive(:warn)

      result = described_class.fetch("widgets") { { fresh: true } }

      expect(result).to eq(fresh: true)
      expect(Rails.logger).to have_received(:warn).with(/Redis unavailable/)
    end

    it "skips Redis entirely in the test environment" do
      allow(Rails.env).to receive(:test?).and_return(true)
      allow(Redis).to receive(:new)

      result = described_class.fetch("widgets") { { skipped: true } }

      expect(result).to eq(skipped: true)
      expect(Redis).not_to have_received(:new)
    end
  end

  describe ".flush_all" do
    it "scans and deletes every namespaced key" do
      fake_redis = instance_double(Redis)
      allow(fake_redis).to receive(:scan).and_return(
        [ "1", [ "dam:search:index:a", "dam:search:index:b" ] ],
        [ "0", [] ]
      )
      allow(fake_redis).to receive(:del)
      allow(Redis).to receive(:new).and_return(fake_redis)

      described_class.flush_all

      expect(fake_redis).to have_received(:del).with("dam:search:index:a", "dam:search:index:b")
    end

    it "logs and swallows Redis errors" do
      fake_redis = instance_double(Redis)
      allow(fake_redis).to receive(:scan).and_raise(Redis::CannotConnectError)
      allow(Redis).to receive(:new).and_return(fake_redis)
      allow(Rails.logger).to receive(:warn)

      expect { described_class.flush_all }.not_to raise_error
      expect(Rails.logger).to have_received(:warn).with(/flush_all failed/)
    end
  end
end
