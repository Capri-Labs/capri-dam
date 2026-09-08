require 'rails_helper'

RSpec.describe Rendition, type: :model do
  describe 'associations' do
    it 'belongs to an asset' do
      expect(create(:rendition).asset).to be_present
    end

    it 'belongs to a storage_backend' do
      expect(create(:rendition).storage_backend).to be_present
    end
  end

  describe 'creation' do
    it 'persists kind, dimensions and content_type' do
      r = create(:rendition, kind: 'web_preview', width: 800, height: 600,
                             content_type: 'image/jpeg')
      r.reload
      expect(r.kind).to eq('web_preview')
      expect(r.width).to eq(800)
      expect(r.height).to eq(600)
    end
  end

  describe 'validations' do
    it 'requires a kind and a storage key' do
      r = described_class.new(asset: create(:asset), storage_backend: create(:storage_backend))
      expect(r).not_to be_valid
      expect(r.errors[:kind]).to be_present
      expect(r.errors[:storage_key]).to be_present
    end

    # The kind is a key other systems match on, not a label, so its shape is
    # constrained even though the vocabulary is open.
    it 'rejects kinds that are not lowercase underscored words' do
      %w[Print\ CMYK print-cmyk PRINT _print print_].each do |bad|
        r = build(:rendition, kind: bad)
        expect(r).not_to be_valid, "expected #{bad.inspect} to be rejected"
        expect(r.errors[:kind]).to be_present
      end
    end

    it 'accepts organisation-specific kinds' do
      expect(build(:rendition, kind: 'broadcast_proxy_v2')).to be_valid
    end

    it 'allows only one rendition of a given kind per asset' do
      first = create(:rendition, kind: 'print_cmyk')
      duplicate = build(:rendition, asset: first.asset, kind: 'print_cmyk')

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:kind].join).to match(/already exists/)
    end

    it 'allows the same kind on a different asset' do
      create(:rendition, kind: 'print_cmyk')
      expect(build(:rendition, kind: 'print_cmyk')).to be_valid
    end

    it 'rejects non-positive dimensions and sizes' do
      expect(build(:rendition, width: 0)).not_to be_valid
      expect(build(:rendition, height: -1)).not_to be_valid
      expect(build(:rendition, file_size: 0)).not_to be_valid
    end

    it 'allows dimensions to be absent, as for a PDF or audio proxy' do
      expect(build(:rendition, width: nil, height: nil, file_size: nil)).to be_valid
    end
  end

  describe 'source' do
    it 'reports a manual upload' do
      expect(create(:rendition, metadata: { 'source' => 'manual' })).to be_manual
    end

    it 'treats anything else as generated' do
      expect(create(:rendition)).not_to be_manual
    end

    it 'scopes by source' do
      manual = create(:rendition, kind: 'print_cmyk', metadata: { 'source' => 'manual' })
      generated = create(:rendition, kind: 'thumbnail')

      expect(described_class.manual).to contain_exactly(manual)
      expect(described_class.generated).to contain_exactly(generated)
    end
  end

  describe 'reserved kinds' do
    it 'recognises the kinds the pipeline owns' do
      expect(build(:rendition, kind: 'thumbnail')).to be_system_kind
      expect(build(:rendition, kind: 'print_cmyk')).not_to be_system_kind
    end
  end

  describe 'url' do
    # Resolved against the backend the bytes were written to, not whichever one
    # happens to be active now.
    it 'asks its own backend, not the active one' do
      rendition = create(:rendition, storage_key: 'renditions/a/b.jpg')
      adapter = instance_double(StorageAdapters::LocalStorageAdapter, url: '/served/b.jpg')
      allow(rendition.storage_backend).to receive(:adapter).and_return(adapter)

      expect(rendition.url).to eq('/served/b.jpg')
      expect(adapter).to have_received(:url).with('renditions/a/b.jpg')
    end
  end

  describe 'destruction' do
    # The row is the only reference to the object; if the row goes, the object
    # is unreachable garbage.
    it 'purges the stored object' do
      rendition = create(:rendition, storage_key: 'renditions/a/b.jpg')
      adapter = instance_double(StorageAdapters::LocalStorageAdapter, delete: true)
      allow_any_instance_of(StorageBackend).to receive(:adapter).and_return(adapter)

      rendition.destroy!

      expect(adapter).to have_received(:delete).with('renditions/a/b.jpg')
    end

    # A storage outage must not leave a user unable to delete a row they have
    # every right to delete.
    it 'still removes the row when the object cannot be purged' do
      rendition = create(:rendition)
      adapter = instance_double(StorageAdapters::LocalStorageAdapter)
      allow(adapter).to receive(:delete).and_raise(StandardError, 'bucket unreachable')
      allow_any_instance_of(StorageBackend).to receive(:adapter).and_return(adapter)

      expect { rendition.destroy! }.to change(described_class, :count).by(-1)
    end

    it 'is purged when its asset is destroyed' do
      rendition = create(:rendition)
      adapter = instance_double(StorageAdapters::LocalStorageAdapter, delete: true)
      allow_any_instance_of(StorageBackend).to receive(:adapter).and_return(adapter)

      expect { rendition.asset.destroy! }.to change(described_class, :count).by(-1)
      expect(adapter).to have_received(:delete)
    end
  end
end
