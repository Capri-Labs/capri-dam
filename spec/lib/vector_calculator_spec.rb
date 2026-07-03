require 'rails_helper'

RSpec.describe VectorCalculator do
  describe '.cosine_similarity' do
    it 'returns 0.0 for nil, empty, and mismatched vectors' do
      expect(described_class.cosine_similarity(nil, [ 1.0 ])).to eq(0.0)
      expect(described_class.cosine_similarity([], [ 1.0 ])).to eq(0.0)
      expect(described_class.cosine_similarity([ 1.0 ], [])).to eq(0.0)
      expect(described_class.cosine_similarity([ 1.0, 2.0 ], [ 1.0 ])).to eq(0.0)
    end

    it 'computes cosine similarity for matching vectors' do
      expect(described_class.cosine_similarity([ 1.0, 2.0, 3.0 ], [ 1.0, 2.0, 3.0 ])).to eq(1.0)
    end

    it 'returns 0.0 when either vector has zero magnitude' do
      expect(described_class.cosine_similarity([ 0.0, 0.0 ], [ 1.0, 2.0 ])).to eq(0.0)
    end
  end
end
