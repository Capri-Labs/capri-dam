# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::FolderPolicyType do
  subject(:type_instance) do
    described_class.allocate.tap do |instance|
      allow(instance).to receive(:object).and_return(policy)
    end
  end

  describe "#group_name" do
    context "when the policy has a user group" do
      let(:group) { instance_double(UserGroup, name: "Designers") }
      let(:policy) { instance_double(FolderPolicy, user_group: group) }

      it "returns the group name" do
        expect(type_instance.group_name).to eq("Designers")
      end
    end

    context "when the policy has no user group" do
      let(:policy) { instance_double(FolderPolicy, user_group: nil) }

      it "returns nil" do
        expect(type_instance.group_name).to be_nil
      end
    end
  end
end
