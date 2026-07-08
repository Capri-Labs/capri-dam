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

  describe '#local_managed?' do
    it 'returns true for local users' do
      expect(build(:user).local_managed?).to be true
    end

    it 'returns false for SSO users' do
      expect(build(:user, :sso).local_managed?).to be false
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

  describe '#inactive_message' do
    it 'returns the default Devise message for active users' do
      expect(build(:user).inactive_message).to eq(:inactive)
    end

    it 'returns account_deactivated for inactive users' do
      expect(build(:user, :inactive).inactive_message).to eq(:account_deactivated)
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
      user.user_groups << [ group1, group2 ]
      create(:folder_policy, :read_only, folder: folder, user_group: group1)
      create(:folder_policy, folder: folder, user_group: group2, modify_access: true)

      perms = user.permissions_for(folder)
      expect(perms[:read]).to be true
      expect(perms[:modify]).to be true
      expect(perms[:delete]).to be false
    end
  end

  describe "#metadata_schema_manager?" do
    it "returns true for admins" do
      admin = build(:user, :admin)
      expect(admin.metadata_schema_manager?).to be true
    end

    it "returns true for members of the administrators group" do
      user  = create(:user)
      group = create(:user_group, :administrators)
      user.user_groups << group
      expect(user.metadata_schema_manager?).to be true
    end

    it "returns true for members of the metadata_users group" do
      user  = create(:user)
      group = create(:user_group, :metadata_users)
      user.user_groups << group
      expect(user.metadata_schema_manager?).to be true
    end

    it "returns false for regular users not in metadata_users" do
      user = create(:user)
      expect(user.metadata_schema_manager?).to be false
    end
  end

  describe '#can_see_folder?' do
    it 'returns the read permission for the folder' do      user = build(:user)
      folder = build(:folder)

      allow(user).to receive(:permissions_for).with(folder).and_return(read: true)

      expect(user.can_see_folder?(folder)).to be true
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

  describe 'callback error handling' do
    let(:user) { build(:user, email: 'warnings@example.com') }

    before do
      allow(Rails.logger).to receive(:warn)
    end

    it 'logs a warning when adding the everyone group fails' do
      everyone_group = instance_double(UserGroup)
      group_memberships = double('group_memberships')

      allow(UserGroup).to receive(:find_by).with(slug: 'everyone').and_return(everyone_group)
      allow(user).to receive(:user_groups).and_return(group_memberships)
      allow(group_memberships).to receive(:include?).with(everyone_group).and_return(false)
      allow(group_memberships).to receive(:<<).with(everyone_group).and_raise(StandardError, 'membership error')

      user.send(:add_to_everyone_group)

      expect(Rails.logger).to have_received(:warn).with('[User] Could not add warnings@example.com to everyone group: membership error')
    end

    it 'logs a warning when creating the default preference fails' do
      allow(user).to receive(:preference).and_return(nil)
      allow(user).to receive(:create_preference).and_raise(StandardError, 'preference error')

      user.send(:create_default_preference)

      expect(Rails.logger).to have_received(:warn).with('[User] Could not create preference for warnings@example.com: preference error')
    end

    it 'does not create a default preference when one already exists' do
      allow(user).to receive(:preference).and_return(instance_double(UserPreference))
      allow(user).to receive(:create_preference)

      user.send(:create_default_preference)

      expect(user).not_to have_received(:create_preference)
    end
  end

  describe ".from_omniauth" do
    let(:auth) do
      OmniAuth::AuthHash.new(
        provider: "keycloak_openid",
        uid:      "kc-uid-42",
        info:     OmniAuth::AuthHash::InfoHash.new(
          email:      "jane@example.com",
          name:       "Jane Doe",
          first_name: "Jane",
          last_name:  "Doe",
          image:      "https://kc.example.com/jane.png",
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

    it "populates first_name, last_name and avatar_url on initial creation" do
      user = User.from_omniauth(auth)
      expect(user.first_name).to eq("Jane")
      expect(user.last_name).to  eq("Doe")
      expect(user.avatar_url).to eq("https://kc.example.com/jane.png")
    end

    it "assigns a username derived from the email local-part with _sso suffix" do
      user = User.from_omniauth(auth)
      expect(user.username).to eq("jane_sso")
    end

    it "syncs the name on re-login" do
      user = User.from_omniauth(auth)
      auth.info.name = "Jane Updated"
      User.from_omniauth(auth)
      expect(user.reload.name).to eq("Jane Updated")
    end

    it "syncs first_name and last_name on re-login" do
      user = User.from_omniauth(auth)
      auth.info.first_name = "Janine"
      auth.info.last_name  = "Updated"
      User.from_omniauth(auth)
      expect(user.reload.first_name).to eq("Janine")
      expect(user.reload.last_name).to  eq("Updated")
    end

    it "syncs avatar_url on re-login" do
      user = User.from_omniauth(auth)
      auth.info.image = "https://kc.example.com/new.png"
      User.from_omniauth(auth)
      expect(user.reload.avatar_url).to eq("https://kc.example.com/new.png")
    end

    context "when name is blank in the token" do
      before { auth.info.name = nil }

      it "falls back to the email local-part as the name" do
        user = User.from_omniauth(auth)
        expect(user.name).to eq("jane")
      end
    end

    context "when a username collision would otherwise occur" do
      before { create(:user, username: "jane_sso") }

      it "assigns a unique username with a counter suffix" do
        user = User.from_omniauth(auth)
        expect(user.username).to eq("jane_sso_2")
      end

      it "keeps incrementing until the username is unique" do
        create(:user, username: "jane_sso_2")
        user = User.from_omniauth(auth)
        expect(user.username).to eq("jane_sso_3")
      end
    end

    context "when the provider/uid combination is not found but email already exists" do
      # If a local user later authenticates via SSO with a different provider uid,
      # from_omniauth creates a second user — document this edge-case behaviour.
      before { create(:user, email: "jane@example.com") }

      it "raises an error due to the unique email constraint" do
        expect { User.from_omniauth(auth) }.to raise_error(ActiveRecord::RecordInvalid)
      end
    end
  end
end
