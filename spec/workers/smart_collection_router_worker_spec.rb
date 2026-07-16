require "rails_helper"

RSpec.describe SmartCollectionRouterWorker, type: :worker do
  subject(:worker) { described_class.new }

  let(:asset_embedding) { double("AssetEmbedding", embedding: [ 0.1, 0.2 ]) }
  let(:asset) do
    double(
      "Asset",
      id: 123,
      asset_embedding: asset_embedding,
      properties: { "status" => "approved" }
    )
  end
  let(:collection) { double("Collection", expires_at: nil, name: "Editorial Picks") }
  let(:rule) do
    double(
      "CollectionRule",
      collection: collection,
      match_mode: "semantic",
      metadata_only?: false,
      metadata_filters: {},
      prompt_vector: [ 0.3, 0.4 ],
      similarity_threshold: 0.8
    )
  end

  before do
    allow(Asset).to receive(:find_by).and_return(asset)
    allow(CollectionRule).to receive_message_chain(:where, :includes).and_return([ rule ])
    allow(VectorCalculator).to receive(:cosine_similarity).and_return(0.9)
    allow(worker).to receive(:map_asset_to_collection!)
  end

  it "returns early when the asset cannot be found" do
    allow(Asset).to receive(:find_by).with(id: 999).and_return(nil)

    worker.perform(999)

    expect(CollectionRule).not_to have_received(:where)
  end

  it "still evaluates metadata-only rules even when the asset has no embedding" do
    metadata_rule = double(
      "CollectionRule",
      collection: collection,
      match_mode: "metadata",
      metadata_only?: true,
      metadata_filters: { "status" => "approved" }
    )
    no_embedding_asset = double("Asset", id: 123, asset_embedding: nil, properties: { "status" => "approved" })
    allow(Asset).to receive(:find_by).with(id: 123).and_return(no_embedding_asset)
    allow(CollectionRule).to receive_message_chain(:where, :includes).and_return([ metadata_rule ])

    worker.perform(123)

    expect(worker).to have_received(:map_asset_to_collection!).with(no_embedding_asset, metadata_rule)
  end

  it "skips semantic/hybrid rules when the asset has no embedding yet" do
    no_embedding_asset = double("Asset", id: 123, asset_embedding: nil, properties: { "status" => "approved" })
    allow(Asset).to receive(:find_by).with(id: 123).and_return(no_embedding_asset)

    worker.perform(123)

    expect(VectorCalculator).not_to have_received(:cosine_similarity)
    expect(worker).not_to have_received(:map_asset_to_collection!)
  end

  it "skips semantic/hybrid rules when the rule has no prompt vector yet" do
    promptless_rule = double(
      "CollectionRule",
      collection: collection,
      match_mode: "semantic",
      metadata_only?: false,
      metadata_filters: {},
      prompt_vector: nil
    )
    allow(CollectionRule).to receive_message_chain(:where, :includes).and_return([ promptless_rule ])

    worker.perform(123)

    expect(VectorCalculator).not_to have_received(:cosine_similarity)
    expect(worker).not_to have_received(:map_asset_to_collection!)
  end

  it "treats blank metadata filters as passing" do
    expect(worker.send(:passes_metadata_filters?, asset, {})).to be(true)
  end

  it "matches metadata filters using 'any of' semantics for array values" do
    tagged_asset = double("Asset", properties: { "tags" => [ "Q3 Campaign", "Internal" ] })

    expect(worker.send(:passes_metadata_filters?, tagged_asset, { "tags" => [ "Q3 Campaign", "Social Media" ] })).to be(true)
    expect(worker.send(:passes_metadata_filters?, tagged_asset, { "tags" => "Embargoed" })).to be(false)
  end

  it "skips expired collections" do
    expired_collection = double("Collection", expires_at: 1.minute.ago, name: "Expired")
    expired_rule = double("CollectionRule",
                          collection: expired_collection,
                          match_mode: "semantic",
                          metadata_only?: false,
                          metadata_filters: {},
                          prompt_vector: [ 0.3 ],
                          similarity_threshold: 0.5)
    allow(CollectionRule).to receive_message_chain(:where, :includes).and_return([ expired_rule ])

    worker.perform(123)

    expect(VectorCalculator).not_to have_received(:cosine_similarity)
    expect(worker).not_to have_received(:map_asset_to_collection!)
  end

  it "skips rules whose metadata filters do not match the asset" do
    mismatched_rule = double("CollectionRule",
                             collection: collection,
                             match_mode: "semantic",
                             metadata_only?: false,
                             metadata_filters: { "status" => "rejected" },
                             prompt_vector: [ 0.3 ],
                             similarity_threshold: 0.5)
    allow(CollectionRule).to receive_message_chain(:where, :includes).and_return([ mismatched_rule ])

    worker.perform(123)

    expect(VectorCalculator).not_to have_received(:cosine_similarity)
    expect(worker).not_to have_received(:map_asset_to_collection!)
  end

  it "does not map assets when similarity stays below the threshold" do
    allow(VectorCalculator).to receive(:cosine_similarity).and_return(0.2)

    worker.perform(123)

    expect(worker).not_to have_received(:map_asset_to_collection!)
  end

  it "maps assets to the collection when similarity meets the threshold" do
    worker.perform(123)

    expect(worker).to have_received(:map_asset_to_collection!).with(asset, rule)
  end
end
