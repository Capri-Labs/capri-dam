require 'rails_helper'

RSpec.describe Reports::Generators::Csv, type: :service do
  let(:snapshot) { build_stubbed(:report_snapshot, report_definition: build_stubbed(:report_definition, name: 'Usage Report')) }

  it 'builds a CSV file with headers and rows' do
    io, filename, content_type = described_class.new([{ name: 'Asset 1', status: 'ready' }], snapshot).generate

    expect(io.read).to include("name,status\nAsset 1,ready")
    expect(filename).to end_with('.csv')
    expect(content_type).to eq('text/csv')
  end

  it 'returns an empty CSV body when there is no data' do
    io, = described_class.new([], snapshot).generate

    expect(io.read).to eq('')
  end
end
