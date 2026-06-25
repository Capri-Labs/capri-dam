require 'rails_helper'

RSpec.describe MetadataImportWorker, type: :worker do
  let(:user) { create(:user) }

  def import_with_csv(csv, **attrs)
    import = create(:metadata_import, user: user, **attrs)
    import.source_file.attach(io: StringIO.new(csv), filename: 'in.csv', content_type: 'text/csv')
    import
  end

  it 'processes the CSV, attaches the results file, records counts and notifies' do
    folder = create(:folder, user: user, name: 'Adventures')
    asset  = create(:asset, title: 'bike.jpg', folder: folder, user: user)

    csv = +"asset_path,copyright\n/Adventures/bike.jpg,WKND Site\n/missing.jpg,X\n"
    import = import_with_csv(csv)

    expect {
      described_class.new.perform(import.id)
    }.to change { user.notifications.count }.by(1)

    import.reload
    expect(import).to be_completed
    expect(import.total_rows).to eq(2)
    expect(import.success_count).to eq(1)
    expect(import.failure_count).to eq(1)
    expect(import.result_file).to be_attached
    expect(import.expires_at).to be_within(1.minute).of(30.days.from_now)
    expect(asset.reload.properties['copyright']).to eq('WKND Site')
    expect(user.notifications.last.title).to match(/import complete/i)
  end

  it 'marks the import failed and notifies when processing raises' do
    import = import_with_csv("asset_path\n/x\n")
    allow(MetadataImportService::CsvProcessor).to receive(:new).and_raise(StandardError.new('kapow'))

    expect { described_class.new.perform(import.id) }.to raise_error(StandardError)
    expect(import.reload).to be_failed
    expect(import.error_message).to eq('kapow')
    expect(user.notifications.last.title).to match(/import failed/i)
  end
end
