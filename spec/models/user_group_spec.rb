require 'rails_helper'

RSpec.describe UserGroup, type: :model do
  # ---------------------------------------------------------------------------
  # Validations
  # ---------------------------------------------------------------------------

  describe "validations" do
    it "is valid with a unique name" do
      expect(build(:user_group)).to be_valid
    end

    it "requires a name" do
      expect(build(:user_group, name: nil)).not_to be_valid
    end

    it "rejects duplicate names (case-insensitive)" do
      create(:user_group, name: "Marketing")
      expect(build(:user_group, name: "marketing")).not_to be_valid
    end

    it "rejects duplicate slugs" do
      create(:user_group, slug: "marketing-team")
      expect(build(:user_group, slug: "marketing-team")).not_to be_valid
    end
  end

  # ---------------------------------------------------------------------------
  # System group protection
  # ---------------------------------------------------------------------------

  describe "system group protection" do
    let!(:everyone)         { create(:user_group, :everyone) }
    let!(:admins)           { create(:user_group, :administrators) }
    let!(:super_admins)     { create(:user_group, :super_administrators) }

    it "prevents deleting the everyone group" do
      expect { everyone.destroy }.not_to change(UserGroup, :count)
      expect(everyone.errors[:base]).to be_present
    end

    it "prevents deleting the administrators group" do
      expect { admins.destroy }.not_to change(UserGroup, :count)
    end

    it "prevents deleting the super-administrators group" do
      expect { super_admins.destroy }.not_to change(UserGroup, :count)
    end

    it "allows deleting a non-system group" do
      group = create(:user_group)
      expect { group.destroy }.to change(UserGroup, :count).by(-1)
    end

    it "prevents changing the slug of a system group" do
      everyone.slug = "new-slug"
      expect(everyone).not_to be_valid
    end

    it "prevents removing the is_system flag" do
      everyone.is_system = false
      expect(everyone).not_to be_valid
    end
  end

  # ---------------------------------------------------------------------------
  # Predicates
  # ---------------------------------------------------------------------------

  describe "predicates" do
    it "identifies system groups via system?" do
      system_group = create(:user_group, :everyone)
      expect(system_group.system?).to be true
    end

    it "returns false for non-system groups" do
      expect(create(:user_group).system?).to be false
    end

    it "correctly identifies everyone group" do
      everyone = create(:user_group, :everyone)
      expect(everyone.everyone?).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # Closure table / hierarchy
  # ---------------------------------------------------------------------------

  describe "closure table" do
    it "creates a self-referential closure entry on create" do
      group = create(:user_group)
      expect(UserGroupClosure.find_by(ancestor_id: group.id, descendant_id: group.id, distance: 0)).to be_present
    end

    it "adds child group paths via add_child" do
      parent = create(:user_group)
      child  = create(:user_group)
      parent.add_child(child)

      expect(
        UserGroupClosure.find_by(ancestor_id: parent.id, descendant_id: child.id, distance: 1)
      ).to be_present
    end

    it "prevents adding a group as its own child" do
      group = create(:user_group)
      expect { group.add_child(group) }.not_to change(UserGroupClosure, :count)
    end
  end

  # ---------------------------------------------------------------------------
  # Members
  # ---------------------------------------------------------------------------

  describe "#all_members" do
    it "returns all users belonging to the group or its descendants" do
      parent = create(:user_group)
      child  = create(:user_group)
      parent.add_child(child)

      user_in_child  = create(:user)
      user_in_parent = create(:user)
      child.users  << user_in_child
      parent.users << user_in_parent

      members = parent.all_members
      expect(members).to include(user_in_child, user_in_parent)
    end
  end
end

