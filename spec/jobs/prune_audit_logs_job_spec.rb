require 'rails_helper'

RSpec.describe PruneAuditLogsJob, type: :job do
  let(:user) { create(:user) }

  # NOTE: these specs deliberately hit the real Postgres trigger
  # (trigger_protect_audit_logs) instead of mocking AuditLog.where/delete_all,
  # so that a regression in the job's disable/re-enable dance is actually
  # caught (a fully-mocked spec previously hid the fact that the job would
  # raise PG::RaiseException in real execution).
  describe '#perform' do
    it 'deletes only audit logs older than the retention window' do
      old_log   = create(:audit_log, user: user, created_at: 91.days.ago)
      young_log = create(:audit_log, user: user, created_at: 89.days.ago)

      expect { described_class.perform_now }
        .to change(AuditLog, :count).by(-1)

      expect(AuditLog.exists?(old_log.id)).to be false
      expect(AuditLog.exists?(young_log.id)).to be true
    end

    it 're-enables the immutability trigger after a successful prune' do
      create(:audit_log, user: user, created_at: 91.days.ago)

      described_class.perform_now

      recent_log = create(:audit_log, user: user)
      expect { recent_log.destroy }
        .to raise_error(ActiveRecord::StatementInvalid, /immutable/)
    end

    it 're-enables the immutability trigger even when the delete raises' do
      allow(AuditLog).to receive(:where).and_raise(StandardError, "boom")

      expect { described_class.perform_now }.to raise_error(StandardError, "boom")

      recent_log = create(:audit_log, user: user)
      expect { recent_log.destroy }
        .to raise_error(ActiveRecord::StatementInvalid, /immutable/)
    end

    it 'does not raise even though the table is immutability-protected' do
      create(:audit_log, user: user, created_at: 100.days.ago)

      expect { described_class.perform_now }.not_to raise_error
    end
  end
end
