require "rails_helper"

RSpec.describe SmartCollectionRouterWorker, type: :worker do
  subject(:worker) { described_class.new }

  let(:asset) do
    double(
      "Asset",
      id: 123,
      vector_embedding: [ 0.1, 0.2 ],
      properties: { "status" => "approved" }
    )
  end
  let(:collection) { double("Collection", expires_at: nil, name: "Editorial Picks") }
  let(:rule) do
    double(
      "CollectionRule",
      collection: collection,
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

  it "returns early when the asset does not have an embedding" do
    blank_asset = double("Asset", vector_embedding: nil)
    allow(Asset).to receive(:find_by).with(id: 123).and_return(blank_asset)

    worker.perform(123)

    expect(CollectionRule).not_to have_received(:where)
  end

  it "treats blank metadata filters as passing" do
    expect(worker.send(:passes_metadata_filters?, asset, {})).to be(true)
  end

  it "skips expired collections" do
    expired_collection = double("Collection", expires_at: 1.minute.ago, name: "Expired")
    expired_rule = double("CollectionRule",
                          collection: expired_collection,
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
end
