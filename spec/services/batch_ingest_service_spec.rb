require 'rails_helper'

RSpec.describe BatchIngestService, type: :service do
  describe '.call' do
    let(:user) { instance_double(User, id: 10) }
    let(:folder) { instance_double(Folder, id: 'folder-20') }
    let(:files) do
      [
        { filename: 'hero.jpg', size: 123 },
        { filename: 'banner.png', size: 456 },
      ]
    end
    let(:result_rows) { [ { 'id' => 101 }, { 'id' => 202 } ] }

    before do
      allow(SecureRandom).to receive(:uuid).and_return('uuid-1', 'uuid-2')
      allow(AssetProcessorWorker).to receive(:perform_async)
      allow(Rails.logger).to receive(:info)
    end

    it 'bulk inserts assets and enqueues a worker for each inserted row' do
      fixed_time = Time.zone.local(2026, 7, 1, 12, 0, 0)
      allow(Time).to receive(:current).and_return(fixed_time)

      expect(Asset).to receive(:insert_all).with(
        [
          {
            user_id: 10,
            folder_id: 'folder-20',
            title: 'hero.jpg',
            status: 'pending',
            uuid: 'uuid-1',
            properties: { original_filename: 'hero.jpg', size: 123 },
            created_at: fixed_time,
            updated_at: fixed_time,
          },
          {
            user_id: 10,
            folder_id: 'folder-20',
            title: 'banner.png',
            status: 'pending',
            uuid: 'uuid-2',
            properties: { original_filename: 'banner.png', size: 456 },
            created_at: fixed_time,
            updated_at: fixed_time,
          },
        ],
        returning: %w[id]
      ).and_return(result_rows)

      expect(described_class.call(user, folder, files)).to eq(2)
      expect(AssetProcessorWorker).to have_received(:perform_async).with(101)
      expect(AssetProcessorWorker).to have_received(:perform_async).with(202)
    end

    it 'returns zero when no files are provided' do
      expect(Asset).to receive(:insert_all).with([], returning: %w[id]).and_return([])

      expect(described_class.call(user, folder, [])).to eq(0)
      expect(AssetProcessorWorker).not_to have_received(:perform_async)
    end
  end
end
