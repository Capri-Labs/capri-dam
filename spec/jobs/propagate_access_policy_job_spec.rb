require "rails_helper"

RSpec.describe PropagateAccessPolicyJob, type: :job do
  let(:user) { create(:user) }
  let(:group) { create(:user_group) }
  let(:root) { create(:folder, user: user) }
  let!(:child) { create(:folder, user: user, parent: root) }
  let!(:grandchild) { create(:folder, user: user, parent: child) }

  it "upserts safe permissions through the folder subtree" do
    described_class.perform_now(
      folder_id: root.id,
      group_id: group.id,
      permissions: { read_access: true, manage_access: true, unsafe_column: true },
      operation: "upsert"
    )

    [ child, grandchild ].each do |folder|
      policy = FolderPolicy.find_by!(folder: folder, user_group: group)
      expect(policy).to be_read_access
      expect(policy).to be_manage_access
    end
  end

  it "removes policies through the folder subtree" do
    create(:folder_policy, folder: child, user_group: group, read_access: true)
    create(:folder_policy, folder: grandchild, user_group: group, read_access: true)

    expect {
      described_class.perform_now(folder_id: root.id, group_id: group.id, permissions: {}, operation: "remove")
    }.to change(FolderPolicy, :count).by(-2)
  end

  it "ignores unknown operations while still recursing without raising" do
    expect {
      described_class.perform_now(folder_id: root.id, group_id: group.id, permissions: {}, operation: "noop")
    }.not_to change(FolderPolicy, :count)
  end
end
