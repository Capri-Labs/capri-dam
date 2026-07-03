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

  it "routes xlsx snapshots to the XLSX generator" do
    xlsx_snapshot = create(
      :report_snapshot,
      format: "xlsx",
      status: :pending,
      report_definition: create(:report_definition, name: "Xlsx Report #{SecureRandom.hex(4)}")
    )
    xlsx_class = class_double("Reports::Generators::Xlsx").as_stubbed_const
    xlsx_generator = instance_double("Reports::Generators::Xlsx")
    allow(xlsx_class).to receive(:new).and_return(xlsx_generator)
    allow(xlsx_generator).to receive(:generate).and_return([ StringIO.new("xlsx"), "usage.xlsx", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" ])

    described_class.execute!(xlsx_snapshot.id)

    expect(xlsx_class).to have_received(:new).with([ { name: "Asset 1" } ], xlsx_snapshot)
    expect(xlsx_snapshot.reload).to be_completed
    expect(xlsx_snapshot.generated_file.filename.to_s).to eq("usage.xlsx")
  end

  it "routes pdf snapshots to the PDF generator" do
    pdf_snapshot = create(
      :report_snapshot,
      format: "pdf",
      status: :pending,
      report_definition: create(:report_definition, name: "Pdf Report #{SecureRandom.hex(4)}")
    )
    pdf_class = class_double("Reports::Generators::Pdf").as_stubbed_const
    pdf_generator = instance_double("Reports::Generators::Pdf")
    allow(pdf_class).to receive(:new).and_return(pdf_generator)
    allow(pdf_generator).to receive(:generate).and_return([ StringIO.new("%PDF"), "usage.pdf", "application/pdf" ])

    described_class.execute!(pdf_snapshot.id)

    expect(pdf_class).to have_received(:new).with([ { name: "Asset 1" } ], pdf_snapshot)
    expect(pdf_snapshot.reload).to be_completed
    expect(pdf_snapshot.generated_file.filename.to_s).to eq("usage.pdf")
  end
end
