require 'rails_helper'

RSpec.describe FolderPolicy, type: :model do
  let(:folder)     { create(:folder, user: create(:user)) }
  let(:user_group) { create(:user_group) }

  describe "validations" do
    it "is valid with all boolean fields set" do
      policy = build(:folder_policy, folder: folder, user_group: user_group)
      expect(policy).to be_valid
    end

    it "requires a folder" do
      expect(build(:folder_policy, folder: nil, user_group: user_group)).not_to be_valid
    end

    it "requires a user_group" do
      expect(build(:folder_policy, folder: folder, user_group: nil)).not_to be_valid
    end

    it "is invalid when boolean fields are nil" do
      policy = build(:folder_policy, folder: folder, user_group: user_group, read_access: nil)
      expect(policy).not_to be_valid
    end
  end

  describe "ACL fields" do
    it "has the correct column names" do
      policy = create(:folder_policy, :full_access, folder: folder, user_group: user_group)
      expect(policy.read_access).to be true
      expect(policy.modify_access).to be true
      expect(policy.create_access).to be true
      expect(policy.delete_access).to be true
      expect(policy.replicate_access).to be true
      expect(policy.manage_access).to be true
    end

    it "defaults all access flags to false" do
      policy = create(:folder_policy, folder: folder, user_group: user_group)
      expect(policy.read_access).to be false
      expect(policy.modify_access).to be false
      expect(policy.create_access).to be false
      expect(policy.delete_access).to be false
      expect(policy.replicate_access).to be false
      expect(policy.explicit_deny).to be false
    end
  end
end
