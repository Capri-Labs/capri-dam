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

  it 'returns early for missing and already completed imports' do
    import = create(:metadata_import, :completed, user: user)

    expect(MetadataImportService::CsvProcessor).not_to receive(:new)

    expect { described_class.new.perform(0) }.not_to raise_error
    expect { described_class.new.perform(import.id) }.not_to change { import.reload.updated_at }
  end

  it 'replaces an existing result file and falls back to the default results filename' do
    import = import_with_csv("asset_path\n/Adventures/bike.jpg\n")
    import.result_file.attach(io: StringIO.new("old"), filename: "old.csv", content_type: "text/csv")
    old_blob_id = import.result_file.blob.id
    allow(import).to receive(:name).and_return("")
    result = instance_double(
      "MetadataImportResult",
      csv_string: "asset_path,import_status\n/Adventures/bike.jpg,ok\n",
      total: 1,
      success: 1,
      failure: 0
    )

    allow(MetadataImportService::CsvProcessor).to receive(:new).and_return(instance_double(MetadataImportService::CsvProcessor, process: result))

    described_class.new.perform(import.id)

    import.reload
    expect(import.result_file).to be_attached
    expect(import.result_file.blob.id).not_to eq(old_blob_id)
    expect(described_class.new.send(:results_filename, import)).to eq("metadata_import_results.csv")
  end

  it 'skips notifications when an import no longer resolves to a user' do
    import = build_stubbed(:metadata_import)
    allow(import).to receive(:user).and_return(nil)

    expect(Notification).not_to receive(:create!)

    described_class.new.send(:notify_user, import, success: true)
  end
end
