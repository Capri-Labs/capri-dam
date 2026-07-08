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

    it "skips immutability checks for unsaved system-like groups" do
      draft_group = build(:user_group, slug: "preview-system-group", is_system: true)

      expect(draft_group).to be_valid
    end

    it "returns early from immutability enforcement for unsaved groups" do
      draft_group = build(:user_group, slug: "preview-system-group", is_system: true)

      expect { draft_group.send(:enforce_system_group_immutability) }.not_to change {
        draft_group.errors.full_messages
      }
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

    it "correctly identifies the built-in metadata_users group" do
      metadata_users = create(:user_group, :metadata_users)
      expect(metadata_users.metadata_users?).to be true
      expect(metadata_users.system?).to be true
      expect(UserGroup::SYSTEM_SLUGS).to include("metadata_users")
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

    describe "#add_child — parent_id sync" do
      it "sets parent_id on the child group" do
        parent = create(:user_group)
        child  = create(:user_group)
        parent.add_child(child)

        expect(child.reload.parent_id).to eq(parent.id)
      end

      it "reflects the child via the child_groups association after add_child" do
        parent = create(:user_group)
        child  = create(:user_group)
        parent.add_child(child)

        expect(parent.reload.child_groups).to include(child)
      end

      it "adds multiple children and lists them all" do
        parent = create(:user_group)
        c1 = create(:user_group)
        c2 = create(:user_group)
        parent.add_child(c1)
        parent.add_child(c2)

        expect(parent.reload.child_groups).to match_array([ c1, c2 ])
      end

      it "does not change parent_id of an unrelated group" do
        parent = create(:user_group)
        other  = create(:user_group)
        child  = create(:user_group)
        parent.add_child(child)

        expect(other.reload.parent_id).to be_nil
      end
    end

    describe "remove_group_member — parent_id sync" do
      it "clears parent_id on the child when removed from parent via controller" do
        parent = create(:user_group)
        child  = create(:user_group)
        parent.add_child(child)
        expect(child.reload.parent_id).to eq(parent.id)

        # Simulate what the controller does
        child.update_column(:parent_id, nil) if child.parent_id == parent.id
        UserGroupClosure.where(ancestor_id: parent.id, descendant_id: child.id).delete_all

        expect(child.reload.parent_id).to be_nil
        expect(parent.reload.child_groups).not_to include(child)
      end

      it "does not clear parent_id if child belongs to a different parent" do
        parent1 = create(:user_group)
        parent2 = create(:user_group)
        child   = create(:user_group)
        parent1.add_child(child)

        # Trying to remove from parent2 should leave parent_id alone
        child.update_column(:parent_id, nil) if child.parent_id == parent2.id

        expect(child.reload.parent_id).to eq(parent1.id)
      end
    end

    describe "multi-level hierarchy" do
      it "creates transitive closure entries (grandparent → grandchild)" do
        grand = create(:user_group)
        mid   = create(:user_group)
        leaf  = create(:user_group)
        grand.add_child(mid)
        mid.add_child(leaf)

        expect(
          UserGroupClosure.find_by(ancestor_id: grand.id, descendant_id: leaf.id, distance: 2)
        ).to be_present
      end

      it "sets parent_id correctly at every level" do
        grand = create(:user_group)
        mid   = create(:user_group)
        leaf  = create(:user_group)
        grand.add_child(mid)
        mid.add_child(leaf)

        expect(mid.reload.parent_id).to eq(grand.id)
        expect(leaf.reload.parent_id).to eq(mid.id)
      end
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
