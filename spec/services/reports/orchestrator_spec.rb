require 'rails_helper'

RSpec.describe Reports::Orchestrator, type: :service do
  let!(:snapshot) { create(:report_snapshot, format: 'csv', status: :pending) }
  let(:generator) { instance_double(Reports::Generators::Csv) }

  before do
    stub_const('Reports::DataFetcher', Class.new do
      def self.fetch(_snapshot); end
    end)
    allow(Reports::DataFetcher).to receive(:fetch).with(instance_of(ReportSnapshot)).and_return([ { name: 'Asset 1' } ])
    allow(Reports::Generators::Csv).to receive(:new).and_return(generator)
  end

  it 'fetches data, generates the report, attaches it, and marks the snapshot completed' do
    allow(generator).to receive(:generate).and_return([ StringIO.new('name\nAsset 1\n'), 'usage.csv', 'text/csv' ])

    described_class.execute!(snapshot.id)

    expect(snapshot.reload).to be_completed
    expect(snapshot.generated_file).to be_attached
    expect(snapshot.generated_file.filename.to_s).to eq('usage.csv')
  end

  it 'marks the snapshot failed and re-raises generation errors' do
    allow(generator).to receive(:generate).and_raise(StandardError, 'broken report')

    expect do
      described_class.execute!(snapshot.id)
    end.to raise_error(StandardError, 'broken report')

    expect(snapshot.reload.status).to eq('failed')
    expect(snapshot.error_message).to eq('broken report')
  end

  it 'raises for unsupported formats' do
    invalid_snapshot = instance_double(
      ReportSnapshot,
      id: snapshot.id,
      processing!: true,
      format: 'json',
      update_columns: true
    )
    allow(ReportSnapshot).to receive(:find).with(snapshot.id).and_return(invalid_snapshot)
    allow(Reports::DataFetcher).to receive(:fetch).with(invalid_snapshot).and_return([])

    expect do
      described_class.execute!(snapshot.id)
    end.to raise_error(ArgumentError, /Unsupported report format/)

    expect(invalid_snapshot).to have_received(:update_columns).with(hash_including(
      status: ReportSnapshot.statuses[:failed],
      error_message: 'Unsupported report format: json'
    ))
  end
end
