require 'rails_helper'

RSpec.describe MetadataImportService::CsvProcessor do
  let(:user) { create(:user) }

  def import_with_csv(csv, **attrs)
    import = create(:metadata_import, user: user, **attrs)
    import.source_file.attach(
      io: StringIO.new(csv), filename: 'import.csv', content_type: 'text/csv'
    )
    import
  end

  describe '#process' do
    it 'raises when the source file is missing' do
      import = create(:metadata_import, user: user)

      expect { described_class.new(import).process }.to raise_error('Source file missing')
    end

    it 'updates metadata for an asset matched by absolute path' do
      folder = create(:folder, user: user, name: 'Adventures')
      asset = create(:asset, title: 'bike.jpg', folder: folder, user: user,
                             properties: { 'description' => '', 'tags' => [] })

      csv = +"asset_path,copyright,tags\n"
      csv << "/Adventures/bike.jpg,WKND Site,bike|outdoor\n"

      result = described_class.new(import_with_csv(csv)).process
      asset.reload

      expect(result.total).to eq(1)
      expect(result.success).to eq(1)
      expect(result.failure).to eq(0)
      expect(result.rows.first.changes).to include(
        include(field: 'copyright', from: nil, to: 'WKND Site'),
        include(field: 'tags', from: [], to: %w[bike outdoor])
      )
      expect(asset.properties['copyright']).to eq('WKND Site')
      expect(asset.properties['tags']).to eq(%w[bike outdoor])
    end

    it 'leaves existing metadata untouched for empty cells' do
      folder = create(:folder, user: user, name: 'Adventures')
      asset = create(:asset, title: 'bike.jpg', folder: folder, user: user,
                             properties: { 'copyright' => 'Original' })

      csv = +"asset_path,copyright,description\n/Adventures/bike.jpg,,New desc\n"
      described_class.new(import_with_csv(csv)).process

      asset.reload
      expect(asset.properties['copyright']).to eq('Original')
      expect(asset.properties['description']).to eq('New desc')
    end

    it 'skips ignored columns' do
      folder = create(:folder, user: user, name: 'Adventures')
      asset = create(:asset, title: 'bike.jpg', folder: folder, user: user)

      csv = +"asset_path,copyright,internal_note\n/Adventures/bike.jpg,ACME,secret\n"
      import = import_with_csv(csv, ignored_columns: [ 'internal_note' ])
      described_class.new(import).process

      asset.reload
      expect(asset.properties['copyright']).to eq('ACME')
      expect(asset.properties).not_to have_key('internal_note')
    end

    it 'marks rows with blank asset paths as failed' do
      csv = +"asset_path,copyright\n   ,ACME\n"

      result = described_class.new(import_with_csv(csv)).process

      expect(result.failure).to eq(1)
      expect(result.rows.first.row_number).to eq(2)
      expect(result.csv_string).to include("Missing 'asset_path' value")
    end

    it 'marks rows with no matching asset as failed' do
      csv = +"asset_path,copyright\n/does/not/exist.jpg,ACME\n"
      result = described_class.new(import_with_csv(csv)).process

      expect(result.total).to eq(1)
      expect(result.failure).to eq(1)
      expect(result.rows.first.resolved_asset_path).to eq('/does/not/exist.jpg')
      expect(result.csv_string).to include('import_status')
      expect(result.csv_string).to match(/fail/i)
    end

    it 'appends status and message columns to the results CSV' do
      folder = create(:folder, user: user, name: 'Adventures')
      create(:asset, title: 'bike.jpg', folder: folder, user: user)

      csv = +"asset_path,copyright\n/Adventures/bike.jpg,ACME\n"
      result = described_class.new(import_with_csv(csv)).process

      header = CSV.parse(result.csv_string).first
      expect(header.last(2)).to eq(%w[import_status import_message])
    end

    it 'updates titles, reports singular property updates, and normalizes missing leading slashes' do
      folder = create(:folder, user: user, name: 'Adventures')
      asset = create(:asset, title: 'bike.jpg', folder: folder, user: user, properties: { 'copyright' => 'Original' })

      csv = +"asset_path,title,copyright\nAdventures/bike.jpg,Renamed Bike,ACME\n"
      result = described_class.new(import_with_csv(csv)).process

      expect(asset.reload.title).to eq('Renamed Bike')
      expect(asset.properties['copyright']).to eq('ACME')
      expect(result.rows.first.changes).to include(
        include(field: 'title', from: 'bike.jpg', to: 'Renamed Bike'),
        include(field: 'copyright', from: 'Original', to: 'ACME')
      )
      expect(result.csv_string).to include('Updated 1 property')
    end

    it 'honours a custom field separator' do
      folder = create(:folder, user: user, name: 'Adventures')
      asset = create(:asset, title: 'bike.jpg', folder: folder, user: user)

      csv = +"asset_path;copyright\n/Adventures/bike.jpg;ACME\n"
      described_class.new(import_with_csv(csv, field_separator: ';')).process

      expect(asset.reload.properties['copyright']).to eq('ACME')
    end

    it 'matches root-level assets and launches workflows when enabled' do
      asset = create(:asset, title: 'root.jpg', folder: nil, user: user, properties: {})
      import = import_with_csv("asset_path,copyright\nroot.jpg,ACME\n", launch_workflows: true)
      allow(Rails.logger).to receive(:info)

      result = described_class.new(import).process

      expect(result.success).to eq(1)
      expect(asset.reload.properties['copyright']).to eq('ACME')
      expect(Rails.logger).to have_received(:info).with(/\[MetadataImport ##{import.id}\] WriteBack workflow launch/)
    end

    it 'does not mutate assets or launch workflows during a dry run' do
      folder = create(:folder, user: user, name: 'Adventures')
      asset = create(:asset, title: 'bike.jpg', folder: folder, user: user,
                             properties: { 'copyright' => 'Original', 'tags' => [ 'legacy' ] })
      import = import_with_csv(
        "asset_path,title,copyright,tags\n/Adventures/bike.jpg,Preview Bike,ACME,bike|outdoor\n",
        launch_workflows: true
      )
      original_updated_at = asset.updated_at
      allow(Rails.logger).to receive(:info)

      result = described_class.new(import, dry_run: true).process

      expect(result.success).to eq(1)
      expect(result.failure).to eq(0)
      expect(result.rows.first.changes).to include(
        include(field: 'title', from: 'bike.jpg', to: 'Preview Bike'),
        include(field: 'copyright', from: 'Original', to: 'ACME'),
        include(field: 'tags', from: [ 'legacy' ], to: %w[bike outdoor])
      )
      expect(asset.reload.title).to eq('bike.jpg')
      expect(asset.properties).to eq('copyright' => 'Original', 'tags' => [ 'legacy' ])
      expect(asset.updated_at.to_i).to eq(original_updated_at.to_i)
      expect(Rails.logger).not_to have_received(:info).with(/WriteBack workflow launch/)
    end

    it 'supports previewing CSV content without an attached source file' do
      folder = create(:folder, user: user, name: 'Adventures')
      create(:asset, title: 'bike.jpg', folder: folder, user: user)
      import = build(:metadata_import, user: user)

      result = described_class.new(
        import,
        dry_run: true,
        source_csv: "asset_path,copyright\n/Adventures/bike.jpg,ACME\n"
      ).process

      expect(result.total).to eq(1)
      expect(result.success).to eq(1)
      expect(result.rows.first.asset_path).to eq('/Adventures/bike.jpg')
    end
  end
end
