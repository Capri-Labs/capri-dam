require 'rails_helper'

RSpec.describe CollectionPolicy, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      expect(build(:collection_policy)).to be_valid
    end

    it 'requires boolean values for the access flags' do
      policy = build(:collection_policy)
      %i[view_access edit_access admin_access explicit_deny].each do |attr|
        policy.public_send("#{attr}=", nil)
        expect(policy).not_to be_valid
      end
    end

    it 'only allows one policy per user_group per collection' do
      collection = create(:collection)
      group = create(:user_group)
      create(:collection_policy, collection: collection, user_group: group)

      duplicate = build(:collection_policy, collection: collection, user_group: group)
      expect(duplicate).not_to be_valid
    end

    it 'allows the same group to have policies on different collections' do
      group = create(:user_group)
      create(:collection_policy, collection: create(:collection), user_group: group)

      expect(build(:collection_policy, collection: create(:collection), user_group: group)).to be_valid
    end
  end

  describe 'associations' do
    it 'belongs to a collection and a user_group' do
      policy = create(:collection_policy)
      expect(policy.collection).to be_present
      expect(policy.user_group).to be_present
    end
  end
end
