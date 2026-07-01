require 'rails_helper'

RSpec.describe Reports::Generators::Xlsx, type: :service do
  let(:snapshot) { build_stubbed(:report_snapshot, report_definition: build_stubbed(:report_definition, name: 'A Very Long Report Name That Exceeds Thirty One Characters')) }

  it 'builds an XLSX workbook with rows' do
    io, filename, content_type = described_class.new([ { name: 'Asset 1', status: 'ready' } ], snapshot).generate

    expect(io).to be_a(StringIO)
    expect(io.string).not_to be_empty
    expect(filename).to end_with('.xlsx')
    expect(content_type).to eq('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
  end

  it 'builds an XLSX workbook for empty datasets' do
    io, = described_class.new([], snapshot).generate

    expect(io.string).not_to be_empty
  end
end
