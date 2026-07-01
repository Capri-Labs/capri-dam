require 'rails_helper'

RSpec.describe Metrics::Aggregator, type: :service do
  describe '.run_daily_snapshot!' do
    let(:date) { Date.new(2026, 6, 30) }

    before do
      allow(Asset).to receive_message_chain(:where, :count).and_return(4)
      allow(WorkflowTask).to receive_message_chain(:where, :count).and_return(2)
      allow(User).to receive_message_chain(:where, :count).and_return(3)
    end

    it 'stores daily metric snapshots for the tracked counters' do
      expect do
        described_class.run_daily_snapshot!(date)
      end.to change(DailyMetric, :count).by(3)

      expect(DailyMetric.find_by(metric_date: date, metric_name: 'assets_created').metric_value).to eq(4)
      expect(DailyMetric.find_by(metric_date: date, metric_name: 'workflows_completed').metric_value).to eq(2)
      expect(DailyMetric.find_by(metric_date: date, metric_name: 'active_users').metric_value).to eq(3)
    end

    it 'updates existing snapshots instead of creating duplicates' do
      create(:daily_metric, metric_date: date, metric_name: 'assets_created', metric_value: 0)
      create(:daily_metric, metric_date: date, metric_name: 'workflows_completed', metric_value: 0)
      create(:daily_metric, metric_date: date, metric_name: 'active_users', metric_value: 0)

      expect do
        described_class.run_daily_snapshot!(date)
      end.not_to change(DailyMetric, :count)

      expect(DailyMetric.find_by(metric_date: date, metric_name: 'assets_created').metric_value).to eq(4)
    end
  end
end
