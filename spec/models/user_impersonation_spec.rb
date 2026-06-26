require "rails_helper"

RSpec.describe User, "#can_be_impersonated_by?", type: :model do
  let(:super_admin)  { create(:user, :super_admin) }
  let(:admin)        { create(:user, :admin) }
  let(:regular_user) { create(:user) }
  let(:another_user) { create(:user) }

  # ── Self-impersonation ────────────────────────────────────────────────────

  it "never allows self-impersonation" do
    expect(admin.can_be_impersonated_by?(admin)).to be false
    expect(super_admin.can_be_impersonated_by?(super_admin)).to be false
    expect(regular_user.can_be_impersonated_by?(regular_user)).to be false
  end

  # ── Super-admin as actor ──────────────────────────────────────────────────

  it "allows super-admin to impersonate a regular user" do
    expect(regular_user.can_be_impersonated_by?(super_admin)).to be true
  end

  it "allows super-admin to impersonate an admin" do
    expect(admin.can_be_impersonated_by?(super_admin)).to be true
  end

  it "does NOT allow super-admin to impersonate another super-admin" do
    expect(super_admin.can_be_impersonated_by?(super_admin)).to be false
  end

  # ── Admin as actor ────────────────────────────────────────────────────────

  it "allows admin to impersonate a regular user" do
    expect(regular_user.can_be_impersonated_by?(admin)).to be true
  end

  it "does NOT allow admin to impersonate a super-admin" do
    expect(super_admin.can_be_impersonated_by?(admin)).to be false
  end

  # ── Explicit grant ────────────────────────────────────────────────────────

  it "allows a non-admin to impersonate when explicitly granted" do
    regular_user.grant_impersonation_to(another_user)
    expect(regular_user.can_be_impersonated_by?(another_user)).to be true
  end

  it "does NOT allow a non-admin without explicit grant" do
    expect(regular_user.can_be_impersonated_by?(another_user)).to be false
  end
end
