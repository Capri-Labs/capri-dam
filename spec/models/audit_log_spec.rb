require 'rails_helper'

RSpec.describe AuditLog, type: :model do
  let(:user)  { create(:user) }
  let(:admin) { create(:user, :admin) }

  describe 'associations' do
    it 'belongs to a user' do
      log = create(:audit_log)
      expect(log.user).to be_present
    end

    it 'optionally belongs to true_user' do
      log = create(:audit_log, user: user, true_user: admin, impersonated: true)
      expect(log.true_user).to eq(admin)
    end
  end

  describe 'creation' do
    it 'records action and subject' do
      log = create(:audit_log, action: 'create', auditable_type: 'Folder')
      expect(log.action).to eq('create')
      expect(log.auditable_type).to eq('Folder')
    end
  end

  # ── .record ──────────────────────────────────────────────────────────────────

  describe '.record' do
    let(:asset) { create(:asset, user: user) }

    it 'creates an entry with the current user as actor' do
      Current.user      = user
      Current.true_user = user

      expect { AuditLog.record(action: 'test', auditable: asset) }
        .to change(AuditLog, :count).by(1)
      expect(AuditLog.last.user).to eq(user)
    end

    it 'records true_user_id and impersonated=true when an impersonation session is active' do
      Current.user      = user    # impersonated account
      Current.true_user = admin   # real actor

      AuditLog.record(action: 'impersonated_action', auditable: asset)
      log = AuditLog.last
      expect(log.true_user).to eq(admin)
      expect(log.impersonated).to be true
    end

    it 'sets impersonated=false for normal (non-impersonated) actions' do
      Current.user      = user
      Current.true_user = user

      AuditLog.record(action: 'normal', auditable: asset)
      expect(AuditLog.last.impersonated).to be false
    end

    it 'returns nil and does not raise when no current user is set' do
      Current.user      = nil
      Current.true_user = nil

      expect {
        result = AuditLog.record(action: 'no_user', auditable: asset)
        expect(result).to be_nil
      }.not_to change(AuditLog, :count)
    end
  end
end
