# frozen_string_literal: true

require "rails_helper"

RSpec.describe FolderContentsCache, type: :service do
  before do
    # FolderContentsCache.fetch short-circuits to an uncached yield in the test
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

      result = described_class.fetch("folder-1", params: { sort: "name", direction: "asc" }, expires_in: 30) { { assets: [ 1, 2, 3 ] } }

      expect(result).to eq(assets: [ 1, 2, 3 ])
      expect(store.keys.first).to start_with("dam:folder_contents:folder-1:")
    end

    it "returns the cached value without re-invoking the block on a hit" do
      fake_redis = instance_double(Redis)
      allow(fake_redis).to receive(:get).and_return({ cached: true }.to_json)
      allow(Redis).to receive(:new).and_return(fake_redis)

      generator = instance_double(Proc, call: { cached: false })

      result = described_class.fetch("folder-1") { generator.call }

      expect(result).to eq(cached: true)
      expect(generator).not_to have_received(:call)
    end

    it "keys the root listing (nil or 'root' folder_id) identically" do
      fake_redis = instance_double(Redis)
      store = {}
      allow(fake_redis).to receive(:get) { |key| store[key] }
      allow(fake_redis).to receive(:setex) { |key, _ttl, value| store[key] = value }
      allow(Redis).to receive(:new).and_return(fake_redis)

      described_class.fetch(nil) { { from: "nil" } }
      # Second call with "root" should hit the same cache entry keyed by "nil".
      result = described_class.fetch("root") { { from: "root_string" } }

      expect(result).to eq(from: "nil")
    end

    it "distinguishes different sort/direction params for the same folder" do
      fake_redis = instance_double(Redis)
      store = {}
      allow(fake_redis).to receive(:get) { |key| store[key] }
      allow(fake_redis).to receive(:setex) { |key, _ttl, value| store[key] = value }
      allow(Redis).to receive(:new).and_return(fake_redis)

      asc  = described_class.fetch("folder-1", params: { sort: "name", direction: "asc" }) { { direction: "asc" } }
      desc = described_class.fetch("folder-1", params: { sort: "name", direction: "desc" }) { { direction: "desc" } }

      expect(asc).to eq(direction: "asc")
      expect(desc).to eq(direction: "desc")
      expect(store.size).to eq(2)
    end

    it "falls back to an uncached value when Redis raises a connection error" do
      fake_redis = instance_double(Redis)
      allow(fake_redis).to receive(:get).and_raise(Redis::CannotConnectError)
      allow(Redis).to receive(:new).and_return(fake_redis)
      allow(Rails.logger).to receive(:warn)

      result = described_class.fetch("folder-1") { { fresh: true } }

      expect(result).to eq(fresh: true)
      expect(Rails.logger).to have_received(:warn).with(/Redis unavailable/)
    end

    it "skips Redis entirely in the test environment" do
      allow(Rails.env).to receive(:test?).and_return(true)
      allow(Redis).to receive(:new)

      result = described_class.fetch("folder-1") { { skipped: true } }

      expect(result).to eq(skipped: true)
      expect(Redis).not_to have_received(:new)
    end
  end

  describe ".bust" do
    it "scans and deletes every cached variant for the given folder id(s)" do
      fake_redis = instance_double(Redis)
      allow(fake_redis).to receive(:scan)
        .with("0", match: "dam:folder_contents:folder-1:*", count: 200)
        .and_return([ "0", [ "dam:folder_contents:folder-1:abc" ] ])
      allow(fake_redis).to receive(:scan)
        .with("0", match: "dam:folder_contents:folder-2:*", count: 200)
        .and_return([ "0", [ "dam:folder_contents:folder-2:def" ] ])
      allow(fake_redis).to receive(:del)
      allow(Redis).to receive(:new).and_return(fake_redis)

      described_class.bust([ "folder-1", "folder-2" ])

      expect(fake_redis).to have_received(:del).with("dam:folder_contents:folder-1:abc")
      expect(fake_redis).to have_received(:del).with("dam:folder_contents:folder-2:def")
    end

    it "normalises nil to the root namespace" do
      fake_redis = instance_double(Redis)
      allow(fake_redis).to receive(:scan)
        .with("0", match: "dam:folder_contents:root:*", count: 200)
        .and_return([ "0", [] ])
      allow(Redis).to receive(:new).and_return(fake_redis)

      expect { described_class.bust(nil) }.not_to raise_error
    end

    it "logs and swallows Redis errors" do
      fake_redis = instance_double(Redis)
      allow(fake_redis).to receive(:scan).and_raise(Redis::CannotConnectError)
      allow(Redis).to receive(:new).and_return(fake_redis)
      allow(Rails.logger).to receive(:warn)

      expect { described_class.bust("folder-1") }.not_to raise_error
      expect(Rails.logger).to have_received(:warn).with(/bust failed/)
    end
  end

  describe ".flush_all" do
    it "scans and deletes every namespaced key" do
      fake_redis = instance_double(Redis)
      allow(fake_redis).to receive(:scan).and_return(
        [ "1", [ "dam:folder_contents:folder-1:a", "dam:folder_contents:folder-1:b" ] ],
        [ "0", [] ]
      )
      allow(fake_redis).to receive(:del)
      allow(Redis).to receive(:new).and_return(fake_redis)

      described_class.flush_all

      expect(fake_redis).to have_received(:del).with("dam:folder_contents:folder-1:a", "dam:folder_contents:folder-1:b")
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
