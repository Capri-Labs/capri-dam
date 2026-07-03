# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::UserType do
  subject(:type_instance) do
    described_class.allocate.tap do |instance|
      allow(instance).to receive(:object).and_return(target_user)
      allow(instance).to receive(:context).and_return(context)
    end
  end

  let(:target_user) { create(:user) }
  let!(:token) { create(:personal_access_token, user: target_user, name: "CLI") }

  describe "#personal_access_tokens" do
    context "when no viewer is present" do
      let(:context) { {} }

      it "returns an empty list" do
        expect(type_instance.personal_access_tokens).to eq([])
      end
    end

    context "when the viewer is another non-admin user" do
      let(:context) { { current_user: create(:user) } }

      it "returns an empty list" do
        expect(type_instance.personal_access_tokens).to eq([])
      end
    end
  end
end
