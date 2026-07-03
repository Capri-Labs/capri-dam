# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::CreateCollection, type: :request do
  subject(:mutation) do
    described_class.allocate.tap do |instance|
      allow(instance).to receive(:context).and_return(current_user: user)
    end
  end

  let(:user) { create(:user) }

  it "returns validation errors when the collection is invalid" do
    result = mutation.resolve(name: "", description: "Broken")

    expect(result[:collection]).to be_nil
    expect(result[:errors]).to include("Name can't be blank")
  end
end
