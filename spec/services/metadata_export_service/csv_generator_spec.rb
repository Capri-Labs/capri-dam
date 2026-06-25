require 'rails_helper'

RSpec.describe MetadataExportService::CsvGenerator do
  let(:user) { create(:user) }

  def build_asset(title, folder, props = {})
    create(:asset, title: title, folder: folder, user: user,
                   properties: { 'description' => '', 'tags' => [] }.merge(props))
  end

  describe '#generate' do
    it 'exports assets in a folder with the base + property columns (all mode)' do
      folder = create(:folder, user: user)
      build_asset('Logo', folder, 'copyright' => 'ACME', 'tags' => %w[brand logo])

      export = create(:metadata_export, user: user, folder: folder,
                                        include_subfolders: false, property_mode: 'all')

      files, total = described_class.new(export).generate

      expect(total).to eq(1)
      expect(files.size).to eq(1)

      header, *rows = CSV.parse(files.first.data)
      expect(header).to include('asset_id', 'title', 'folder_path', 'copyright')
      expect(rows.first).to include('ACME')
      # Multi-value arrays are flattened with a "; " separator.
      expect(rows.first.join(',')).to include('brand; logo')
    end

    it 'cascades into subfolders when include_subfolders is true' do
      root  = create(:folder, user: user)
      child = create(:folder, parent: root, user: user)
      build_asset('Root Asset', root)
      build_asset('Child Asset', child)

      export = create(:metadata_export, user: user, folder: root, include_subfolders: true)
      _files, total = described_class.new(export).generate

      expect(total).to eq(2)
    end

    it 'limits columns to the selected properties in selective mode' do
      folder = create(:folder, user: user)
      build_asset('Logo', folder, 'copyright' => 'ACME', 'secret' => 'hidden')

      export = create(:metadata_export, user: user, folder: folder,
                                        property_mode: 'selective', selected_properties: [ 'copyright' ])

      files, = described_class.new(export).generate
      header = CSV.parse(files.first.data).first

      expect(header).to include('copyright')
      expect(header).not_to include('secret')
    end

    it 'always emits at least one (header-only) file when there are no assets' do
      folder = create(:folder, user: user)
      export = create(:metadata_export, user: user, folder: folder)

      files, total = described_class.new(export).generate
      expect(total).to eq(0)
      expect(files.size).to eq(1)
      expect(CSV.parse(files.first.data).first).to include('asset_id')
    end

    it 'splits output into multiple files beyond the row ceiling' do
      folder = create(:folder, user: user)
      build_asset('A', folder)
      build_asset('B', folder)
      build_asset('C', folder)

      export = create(:metadata_export, user: user, folder: folder)
      stub_const('MetadataExport::MAX_ROWS_PER_FILE', 2)

      files, total = described_class.new(export).generate
      expect(total).to eq(3)
      expect(files.size).to eq(2)
      expect(files.map(&:filename)).to all(match(/_part\d+\.csv\z/))
    end
  end
end
