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

  it "returns early when the export no longer exists" do
    expect { described_class.new.perform(0) }.not_to raise_error
  end

  it "replaces previously attached export files" do
    export = create(:metadata_export, user: user)

    File.open(Rails.root.join("spec/fixtures/files/metadata_import_sample.csv")) do |file|
      export.files.attach(io: file, filename: "old.csv", content_type: "text/csv")
    end

    described_class.new.perform(export.id)

    export.reload
    expect(export.files.attachments.size).to eq(1)
    expect(export.files.first.filename.to_s).not_to eq("old.csv")
  end

  it "skips notifications when the export has no user" do
    export = build_stubbed(:metadata_export)
    allow(export).to receive(:user).and_return(nil)

    expect { described_class.new.send(:notify_user, export, success: true) }.not_to change(Notification, :count)
  end

  it 'marks the export failed and notifies on error' do
    export = create(:metadata_export, user: user)
    allow(MetadataExportService::CsvGenerator).to receive(:new).and_raise(StandardError.new('boom'))

    expect { described_class.new.perform(export.id) }.to raise_error(StandardError)
    expect(export.reload).to be_failed
    expect(export.error_message).to eq('boom')
    expect(user.notifications.last.title).to match(/export failed/i)
  end

  it "re-raises lookup errors before an export is loaded" do
    allow(MetadataExport).to receive(:find_by).and_raise(StandardError, "lookup failed")

    expect { described_class.new.perform(123) }.to raise_error(StandardError, "lookup failed")
  end
end
