require 'rails_helper'

RSpec.describe TransformationPreset, type: :model do
  describe 'factory' do
    it 'builds a valid record' do
      expect(build(:transformation_preset)).to be_a(TransformationPreset)
    end
  end

  describe 'persisting' do
    it 'saves and can be retrieved' do
      preset = create(:transformation_preset, name: 'Thumb 200x200', slug: 'thumb-200')
      found = TransformationPreset.find(preset.id)
      expect(found.name).to eq('Thumb 200x200')
      expect(found.params).to eq({ 'width' => 100, 'format' => 'webp' })
    end
  end
end
