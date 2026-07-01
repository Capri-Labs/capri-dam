require 'rails_helper'

RSpec.describe Reports::Generators::Base, type: :service do
  subject(:generator) { described_class.new([], snapshot) }

  let(:snapshot) { build_stubbed(:report_snapshot, report_definition: build_stubbed(:report_definition, name: 'Asset Inventory')) }

  describe '#generate' do
    it 'raises until implemented by a subclass' do
      expect { generator.generate }.to raise_error(NotImplementedError)
    end
  end

  describe '#default_filename' do
    it 'parameterizes the report name and appends a timestamp' do
      fixed_time = Time.zone.local(2026, 7, 1, 12, 34, 56)
      allow(Time).to receive(:current).and_return(fixed_time)

      expect(generator.send(:default_filename, 'csv')).to eq('asset-inventory_20260701_123456.csv')
    end
  end
end
