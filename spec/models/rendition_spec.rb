require 'rails_helper'

RSpec.describe Rendition, type: :model do
  describe 'associations' do
    it 'belongs to an asset' do
      rendition = create(:rendition)
      expect(rendition.asset).to be_present
    end

    it 'belongs to a storage_backend' do
      rendition = create(:rendition)
      expect(rendition.storage_backend).to be_present
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
end
