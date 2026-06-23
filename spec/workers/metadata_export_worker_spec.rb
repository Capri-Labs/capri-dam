require 'rails_helper'

RSpec.describe MetadataExportWorker, type: :worker do
  let(:user) { create(:user) }

  it 'generates CSVs, attaches them, sets expiry and notifies the user' do
    folder = create(:folder, user: user)
    create(:asset, folder: folder, user: user, properties: { 'copyright' => 'ACME' })

    export = create(:metadata_export, user: user, folder: folder, include_subfolders: false)

    expect {
      described_class.new.perform(export.id)
    }.to change { user.notifications.count }.by(1)

    export.reload
    expect(export).to be_completed
    expect(export.total_assets).to eq(1)
    expect(export.file_count).to eq(1)
    expect(export.files).to be_attached
    expect(export.expires_at).to be_within(1.minute).of(30.days.from_now)
    expect(user.notifications.last.title).to match(/export ready/i)
  end

  it 'is idempotent for an already-completed export' do
    export = create(:metadata_export, :completed, user: user)
    expect { described_class.new.perform(export.id) }
      .not_to change { user.notifications.count }
  end

  it 'marks the export failed and notifies on error' do
    export = create(:metadata_export, user: user)
    allow(MetadataExportService::CsvGenerator).to receive(:new).and_raise(StandardError.new('boom'))

    expect { described_class.new.perform(export.id) }.to raise_error(StandardError)
    expect(export.reload).to be_failed
    expect(export.error_message).to eq('boom')
    expect(user.notifications.last.title).to match(/export failed/i)
  end
end

