require 'rails_helper'

RSpec.describe PruneAuditLogsJob, type: :job do
  describe '#perform' do
    it 'deletes audit logs older than 90 days' do
      relation = instance_double(ActiveRecord::Relation, delete_all: 3)

      expect(AuditLog).to receive(:where) do |query, timestamp|
        expect(query).to eq('created_at < ?')
        expect(timestamp).to be_within(5.seconds).of(90.days.ago)
        relation
      end

      expect(relation).to receive(:delete_all)

      described_class.perform_now
    end
  end
end
