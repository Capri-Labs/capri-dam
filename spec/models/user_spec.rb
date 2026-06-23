require 'rails_helper'

RSpec.describe User, type: :model do
  it "is valid with valid attributes" do
    user = build(:user)
    expect(user).to be_valid
  end

  it "is valid without a username (email is the identity)" do
    user = build(:user, username: nil)
    expect(user).to be_valid
  end

  it "is invalid without an email" do
    user = build(:user, email: nil)
    expect(user).to_not be_valid
  end

  it "enforces unique emails (case-insensitive)" do
    create(:user, email: "owner@example.com")
    duplicate = build(:user, email: "OWNER@example.com")
    expect(duplicate).to_not be_valid
  end
end