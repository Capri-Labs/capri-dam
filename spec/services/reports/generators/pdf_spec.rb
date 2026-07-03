require 'rails_helper'

RSpec.describe Reports::Generators::Pdf, type: :service do
  let(:snapshot) { build_stubbed(:report_snapshot, report_definition: build_stubbed(:report_definition, name: 'Usage Report'), parameters: { status: 'ready' }) }

  it 'builds a PDF document for populated data' do
    io, filename, content_type = described_class.new([ { name: 'Asset 1', status: 'ready' } ], snapshot).generate

    expect(io.read).to start_with('%PDF')
    expect(filename).to end_with('.pdf')
    expect(content_type).to eq('application/pdf')
  end

  it 'builds a PDF document when there is no data' do
    io, = described_class.new([], snapshot).generate

    expect(io.read).to start_with('%PDF')
  end

  it 'builds a PDF document when no filters were applied' do
    blank_snapshot = build_stubbed(:report_snapshot, report_definition: build_stubbed(:report_definition, name: 'Usage Report'), parameters: {})

    io, = described_class.new([ { name: 'Asset 1', status: 'ready' } ], blank_snapshot).generate

    expect(io.read).to start_with('%PDF')
  end

  it 'renders multiple data rows without raising' do
    io, = described_class.new([
      { name: 'Asset 1', status: 'ready' },
      { name: 'Asset 2', status: 'draft' },
    ], snapshot).generate

    expect(io.read).to start_with('%PDF')
  end
end
