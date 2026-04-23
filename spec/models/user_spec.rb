require 'rails_helper'

RSpec.describe User, type: :model do
  it "is valid with valid attributes" do
    user = build(:user)
    expect(user).to be_valid
  end

  it "is invalid without a username" do
    user = build(:user, username: nil)
    expect(user).to_not be_valid
  end

  it "enforces unique usernames" do
    create(:user, username: "unique_guy")
    duplicate = build(:user, username: "unique_guy")
    expect(duplicate).to_not be_valid
  end
end