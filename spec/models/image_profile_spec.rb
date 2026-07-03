# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ImageProfile, type: :model do
  # ── Factories ────────────────────────────────────────────────────────────────
  subject(:profile) { build(:image_profile) }

  # ── Validations ──────────────────────────────────────────────────────────────
  describe 'validations' do
    it 'is valid with default attributes' do
      expect(build(:image_profile)).to be_valid
    end

    it 'requires a name' do
      profile = build(:image_profile, name: '')
      expect(profile).not_to be_valid
      expect(profile.errors[:name]).to include("can't be blank")
    end

    it 'requires a valid crop_type' do
      profile = build(:image_profile, crop_type: 'unknown')
      expect(profile).not_to be_valid
      expect(profile.errors[:crop_type]).to be_present
    end

    it 'accepts smart_crop as a valid crop_type' do
      expect(build(:image_profile, crop_type: 'smart_crop')).to be_valid
    end

    it 'accepts none as a valid crop_type' do
      expect(build(:image_profile, crop_type: 'none')).to be_valid
    end

    context 'unsharp mask range validations' do
      it 'rejects amount outside 0-5' do
        profile = build(:image_profile, unsharp_mask: { 'amount' => 6.0, 'radius' => 0.2, 'threshold' => 2 })
        expect(profile).not_to be_valid
        expect(profile.errors[:unsharp_mask]).to include(match(/amount/))
      end

      it 'rejects radius outside 0-250' do
        profile = build(:image_profile, unsharp_mask: { 'amount' => 1.0, 'radius' => 300, 'threshold' => 2 })
        expect(profile).not_to be_valid
        expect(profile.errors[:unsharp_mask]).to include(match(/radius/))
      end

      it 'rejects threshold outside 0-255' do
        profile = build(:image_profile, unsharp_mask: { 'amount' => 1.0, 'radius' => 0.5, 'threshold' => 300 })
        expect(profile).not_to be_valid
        expect(profile.errors[:unsharp_mask]).to include(match(/threshold/))
      end

      it 'accepts valid boundary values' do
        profile = build(:image_profile, unsharp_mask: { 'amount' => 0, 'radius' => 250, 'threshold' => 255 })
        expect(profile).to be_valid
      end

      it 'skips unsharp mask validation when the setting is blank' do
        profile = build(:image_profile, unsharp_mask: nil)
        expect(profile).to be_valid
      end
    end

    context 'responsive crops structure' do
      it 'is valid with a well-formed crops array' do
        profile = build(:image_profile, :with_smart_crop)
        expect(profile).to be_valid
      end

      it 'rejects crops with missing name' do
        profile = build(:image_profile, responsive_crops: [ { 'width' => 400, 'height' => 300 } ])
        expect(profile).not_to be_valid
        expect(profile.errors[:responsive_crops]).to be_present
      end

      it 'rejects crops with zero width' do
        profile = build(:image_profile, responsive_crops: [ { 'name' => 'Bad', 'width' => 0, 'height' => 300 } ])
        expect(profile).not_to be_valid
      end

      it 'accepts an empty crops array' do
        profile = build(:image_profile, responsive_crops: [])
        expect(profile).to be_valid
      end

      it 'rejects non-array responsive crops' do
        profile = build(:image_profile, responsive_crops: { 'name' => 'Bad' })
        expect(profile).not_to be_valid
        expect(profile.errors[:responsive_crops]).to include('must be an array')
      end
    end

    context 'swatch dimensions' do
      it 'rejects non-positive swatch_width' do
        profile = build(:image_profile, swatch_width: 0)
        expect(profile).not_to be_valid
      end

      it 'rejects non-positive swatch_height' do
        profile = build(:image_profile, swatch_height: -10)
        expect(profile).not_to be_valid
      end

      it 'allows nil swatch dimensions when swatch disabled' do
        profile = build(:image_profile, swatch_enabled: false, swatch_width: nil, swatch_height: nil)
        expect(profile).to be_valid
      end
    end
  end

  # ── Scopes ───────────────────────────────────────────────────────────────────
  describe 'scopes' do
    let!(:active_profile)  { create(:image_profile) }
    let!(:deleted_profile) { create(:image_profile, :deleted) }

    describe '.active' do
      it 'returns only non-deleted profiles' do
        expect(ImageProfile.active).to include(active_profile)
        expect(ImageProfile.active).not_to include(deleted_profile)
      end
    end
  end

  # ── Soft Delete ───────────────────────────────────────────────────────────────
  describe '#soft_delete!' do
    let(:profile) { create(:image_profile) }

    it 'sets deleted_at timestamp' do
      expect { profile.soft_delete! }.to change { profile.deleted_at }.from(nil)
    end

    it 'excludes profile from .active scope after deletion' do
      profile.soft_delete!
      expect(ImageProfile.active).not_to include(profile)
    end
  end

  # ── effective_unsharp_mask ────────────────────────────────────────────────────
  describe '#effective_unsharp_mask' do
    it 'returns stored values merged over defaults' do
      profile = build(:image_profile, unsharp_mask: { 'amount' => 3.0, 'radius' => 0.5, 'threshold' => 10 })
      result  = profile.effective_unsharp_mask
      expect(result['amount']).to eq(3.0)
      expect(result['radius']).to eq(0.5)
    end

    it 'falls back to defaults when unsharp_mask is blank' do
      profile = build(:image_profile, unsharp_mask: nil)
      result  = profile.effective_unsharp_mask
      expect(result['amount']).to eq(1.75)
      expect(result['radius']).to eq(0.2)
      expect(result['threshold']).to eq(2)
    end
  end

  # ── .applicable_mime_type? ───────────────────────────────────────────────────
  describe '.applicable_mime_type?' do
    it 'returns true for standard image MIME types' do
      expect(ImageProfile.applicable_mime_type?('image/jpeg')).to be true
      expect(ImageProfile.applicable_mime_type?('image/png')).to  be true
      expect(ImageProfile.applicable_mime_type?('image/webp')).to be true
    end

    it 'returns false for PDF' do
      expect(ImageProfile.applicable_mime_type?('application/pdf')).to be false
    end

    it 'returns false for animated GIF' do
      expect(ImageProfile.applicable_mime_type?('image/gif')).to be false
    end

    it 'returns false for InDesign files' do
      expect(ImageProfile.applicable_mime_type?('application/x-indesign')).to be false
    end

    it 'returns false for non-image MIME types' do
      expect(ImageProfile.applicable_mime_type?('video/mp4')).to be false
      expect(ImageProfile.applicable_mime_type?('application/zip')).to be false
    end
  end

  # ── Associations ─────────────────────────────────────────────────────────────
  describe 'associations' do
    it 'has many folder_assignments' do
      profile = create(:image_profile)
      expect(profile.folder_assignments).to be_empty
    end

    it 'destroys folder_assignments on destroy' do
      profile    = create(:image_profile)
      assignment = ImageProfileFolderAssignment.create!(
        image_profile: profile,
        folder_id:     SecureRandom.uuid
      )
      expect { profile.destroy }.to change { ImageProfileFolderAssignment.count }.by(-1)
    end
  end
end
