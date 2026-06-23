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
  end

  describe 'associations' do
    it 'belongs to a collection' do
      rule = create(:collection_rule)
      expect(rule.collection).to be_present
    end
  end
end
