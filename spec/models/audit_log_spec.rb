require 'rails_helper'

RSpec.describe AuditLog, type: :model do
  describe 'associations' do
    it 'belongs to a user' do
      log = create(:audit_log)
      expect(log.user).to be_present
    end
  end

  describe 'creation' do
    it 'records action and subject' do
      log = create(:audit_log, action: 'create', auditable_type: 'Folder')
      expect(log.action).to eq('create')
      expect(log.auditable_type).to eq('Folder')
    end
  end
end
