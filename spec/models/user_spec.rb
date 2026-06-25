require 'rails_helper'

RSpec.describe User, type: :model do
  # ---------------------------------------------------------------------------
  # Basic validations
  # ---------------------------------------------------------------------------

  describe "validations" do
    it "is valid with valid attributes" do
      expect(build(:user)).to be_valid
    end

    it "is valid without a username" do
      expect(build(:user, username: nil)).to be_valid
    end

    it "is invalid without an email" do
      expect(build(:user, email: nil)).not_to be_valid
    end

    it "enforces unique emails (case-insensitive)" do
      create(:user, email: "owner@example.com")
      expect(build(:user, email: "OWNER@example.com")).not_to be_valid
    end
  end

  # ---------------------------------------------------------------------------
  # Identity helpers
  # ---------------------------------------------------------------------------

  describe "#full_name" do
    it "returns first + last name when both present" do
      user = build(:user, first_name: "Jane", last_name: "Doe")
      expect(user.full_name).to eq("Jane Doe")
    end

    it "falls back to email when names are blank" do
      user = build(:user, first_name: nil, last_name: nil, name: "")
      expect(user.full_name).to eq(user.email)
    end
  end

  describe "#display_name" do
    it "prefers the name field" do
      user = build(:user, name: "Jane Doe", first_name: "Jane")
      expect(user.display_name).to eq("Jane Doe")
    end
  end

  describe "#sso_managed?" do
    it "returns true for SSO users" do
      expect(build(:user, :sso).sso_managed?).to be true
    end

    it "returns false for local users" do
      expect(build(:user).sso_managed?).to be false
    end
  end

  # ---------------------------------------------------------------------------
  # Everyone group auto-membership
  # ---------------------------------------------------------------------------

  describe "everyone group auto-membership" do
    let!(:everyone) { create(:user_group, :everyone) }

    it "adds new user to the everyone group" do
      user = create(:user)
      expect(user.user_groups).to include(everyone)
    end
  end

  # ---------------------------------------------------------------------------
  # Lifecycle
  # ---------------------------------------------------------------------------

  describe "#deactivate! / #reactivate!" do
    let(:user) { create(:user) }

    it "sets active to false on deactivate!" do
      user.deactivate!
      expect(user.reload.active).to be false
    end

    it "sets active to true on reactivate!" do
      user.update!(active: false)
      user.reactivate!
      expect(user.reload.active).to be true
    end
  end

  describe "#active_for_authentication?" do
    it "returns false for deactivated users" do
      user = build(:user, :inactive)
      expect(user.active_for_authentication?).to be false
    end

    it "returns true for active users" do
      user = build(:user)
      expect(user.active_for_authentication?).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # Permissions
  # ---------------------------------------------------------------------------

  describe "#permissions_for" do
    let(:folder) { create(:folder, user: create(:user)) }

    it "returns full permissions for admins" do
      admin = build(:user, :admin)
      perms = admin.permissions_for(folder)
      expect(perms[:read]).to be true
      expect(perms[:modify]).to be true
      expect(perms[:create]).to be true
      expect(perms[:delete]).to be true
    end

    it "denies all when explicit_deny is set" do
      user  = create(:user)
      group = create(:user_group)
      user.user_groups << group
      create(:folder_policy, :explicit_deny, folder: folder, user_group: group)

      perms = user.permissions_for(folder)
      expect(perms.values).to all(be false)
    end

    it "aggregates permissions with OR across groups" do
      user   = create(:user)
      group1 = create(:user_group)
      group2 = create(:user_group)
      user.user_groups << [group1, group2]
      create(:folder_policy, :read_only, folder: folder, user_group: group1)
      create(:folder_policy, folder: folder, user_group: group2, modify_access: true)

      perms = user.permissions_for(folder)
      expect(perms[:read]).to be true
      expect(perms[:modify]).to be true
      expect(perms[:delete]).to be false
    end
  end

  # ---------------------------------------------------------------------------
  # Impersonation
  # ---------------------------------------------------------------------------

  describe "impersonation" do
    let(:target)      { create(:user) }
    let(:impersonator) { create(:user) }

    it "grants impersonation access" do
      target.grant_impersonation_to(impersonator)
      expect(target.can_be_impersonated_by?(impersonator)).to be true
    end

    it "revokes impersonation access" do
      target.grant_impersonation_to(impersonator)
      target.revoke_impersonation_from(impersonator)
      expect(target.can_be_impersonated_by?(impersonator)).to be false
    end

    it "lists impersonating accounts" do
      target.grant_impersonation_to(impersonator)
      expect(target.impersonators).to include(impersonator)
    end
  end

  # ---------------------------------------------------------------------------
  # SSO sync
  # ---------------------------------------------------------------------------

  describe ".from_omniauth" do
    let(:auth) do
      OmniAuth::AuthHash.new(
        provider: 'keycloak_openid',
        uid:      'kc-uid-42',
        info:     OmniAuth::AuthHash::InfoHash.new(
          email:      'jane@example.com',
          name:       'Jane Doe',
          first_name: 'Jane',
          last_name:  'Doe',
          image:      nil
        )
      )
    end

    it "creates a new user on first login" do
      expect { User.from_omniauth(auth) }.to change(User, :count).by(1)
    end

    it "finds the existing user on subsequent logins" do
      User.from_omniauth(auth)
      expect { User.from_omniauth(auth) }.not_to change(User, :count)
    end

    it "syncs the name on re-login" do
      user = User.from_omniauth(auth)
      auth.info.name = "Jane Updated"
      User.from_omniauth(auth)
      expect(user.reload.name).to eq("Jane Updated")
    end
  end
end

