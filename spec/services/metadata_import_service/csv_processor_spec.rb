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
    it 'updates metadata for an asset matched by absolute path' do
      folder = create(:folder, user: user, name: 'Adventures')
      asset  = create(:asset, title: 'bike.jpg', folder: folder, user: user,
                              properties: { 'description' => '', 'tags' => [] })

      csv = +"asset_path,copyright,tags\n"
      csv << "/Adventures/bike.jpg,WKND Site,bike|outdoor\n"

      result = described_class.new(import_with_csv(csv)).process
      asset.reload

      expect(result.total).to eq(1)
      expect(result.success).to eq(1)
      expect(result.failure).to eq(0)
      expect(asset.properties['copyright']).to eq('WKND Site')
      expect(asset.properties['tags']).to eq(%w[bike outdoor])
    end

    it 'leaves existing metadata untouched for empty cells' do
      folder = create(:folder, user: user, name: 'Adventures')
      asset  = create(:asset, title: 'bike.jpg', folder: folder, user: user,
                              properties: { 'copyright' => 'Original' })

      csv = +"asset_path,copyright,description\n/Adventures/bike.jpg,,New desc\n"
      described_class.new(import_with_csv(csv)).process

      asset.reload
      expect(asset.properties['copyright']).to eq('Original')
      expect(asset.properties['description']).to eq('New desc')
    end

    it 'skips ignored columns' do
      folder = create(:folder, user: user, name: 'Adventures')
      asset  = create(:asset, title: 'bike.jpg', folder: folder, user: user)

      csv = +"asset_path,copyright,internal_note\n/Adventures/bike.jpg,ACME,secret\n"
      import = import_with_csv(csv, ignored_columns: [ 'internal_note' ])
      described_class.new(import).process

      asset.reload
      expect(asset.properties['copyright']).to eq('ACME')
      expect(asset.properties).not_to have_key('internal_note')
    end

    it 'marks rows with no matching asset as failed' do
      csv = +"asset_path,copyright\n/does/not/exist.jpg,ACME\n"
      result = described_class.new(import_with_csv(csv)).process

      expect(result.total).to eq(1)
      expect(result.failure).to eq(1)
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

    it 'honours a custom field separator' do
      folder = create(:folder, user: user, name: 'Adventures')
      asset  = create(:asset, title: 'bike.jpg', folder: folder, user: user)

      csv = +"asset_path;copyright\n/Adventures/bike.jpg;ACME\n"
      described_class.new(import_with_csv(csv, field_separator: ';')).process

      expect(asset.reload.properties['copyright']).to eq('ACME')
    end
  end
end
