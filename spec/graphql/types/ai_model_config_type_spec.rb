require "rails_helper"

RSpec.describe Types::AiModelConfigType do
  let(:config) { build_stubbed(:ai_model_config) }

  it "authorizes admin users only" do
    expect(described_class.authorized?(config, { current_user: create(:user, :admin) })).to be(true)
    expect(described_class.authorized?(config, { current_user: create(:user) })).to be(false)
    expect(described_class.authorized?(config, { current_user: nil })).to be_nil
  end
end
