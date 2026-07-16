require 'rails_helper'

RSpec.describe CollectionRule, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      expect(build(:collection_rule)).to be_valid
    end

    it 'requires a semantic_prompt' do
      expect(build(:collection_rule, semantic_prompt: nil)).not_to be_valid
    end

    it 'requires similarity_threshold between 0 and 1' do
      expect(build(:collection_rule, similarity_threshold: 1.5)).not_to be_valid
      expect(build(:collection_rule, similarity_threshold: 0.0)).not_to be_valid
      expect(build(:collection_rule, similarity_threshold: 0.75)).to be_valid
    end

    it 'defaults match_mode to semantic' do
      expect(build(:collection_rule).match_mode).to eq('semantic')
    end

    it 'rejects an unknown match_mode' do
      expect(build(:collection_rule, match_mode: 'bogus')).not_to be_valid
    end

    context 'when match_mode is metadata' do
      it 'does not require a semantic_prompt' do
        expect(build(:collection_rule, :metadata)).to be_valid
      end

      it 'requires metadata_filters' do
        expect(build(:collection_rule, :metadata, metadata_filters: {})).not_to be_valid
      end
    end

    context 'when match_mode is hybrid' do
      it 'requires both semantic_prompt and metadata_filters' do
        expect(build(:collection_rule, :hybrid)).to be_valid
        expect(build(:collection_rule, :hybrid, semantic_prompt: nil)).not_to be_valid
        expect(build(:collection_rule, :hybrid, metadata_filters: {})).not_to be_valid
      end
    end
  end

  describe '#metadata_only?/#semantic_only?/#hybrid?' do
    it 'reflects the configured match_mode' do
      expect(build(:collection_rule, :metadata)).to be_metadata_only
      expect(build(:collection_rule)).to be_semantic_only
      expect(build(:collection_rule, :hybrid)).to be_hybrid
    end
  end

  describe 'associations' do
    it 'belongs to a collection' do
      rule = create(:collection_rule)
      expect(rule.collection).to be_present
    end
  end
end
