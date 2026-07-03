require "rails_helper"

RSpec.describe UserImpersonator, type: :model do
  it "rejects self impersonation" do
    user = create(:user)
    grant = build(:user_impersonator, user: user, impersonator: user)

    expect(grant).not_to be_valid
    expect(grant.errors[:base]).to include("A user cannot impersonate themselves.")
  end
end
