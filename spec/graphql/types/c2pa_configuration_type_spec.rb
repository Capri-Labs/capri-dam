# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::C2paConfigurationType do
  let(:config) { build_stubbed(:c2pa_configuration) }

  it "allows admins" do
    expect(described_class.authorized?(config, { current_user: build_stubbed(:user, :admin) })).to be(true)
  end

  it "rejects non-admins" do
    expect(described_class.authorized?(config, { current_user: build_stubbed(:user) })).to be(false)
  end
end
