require 'rails_helper'

RSpec.describe AiTagSuggestion, type: :model do
  describe 'normalisation' do
    # Labels are matched on, not just displayed. Without one canonical form,
    # "Sunset", "sunset " and "sunset" are three tags that look like one.
    it 'collapses case and surrounding whitespace' do
      expect(described_class.normalise('  Sunset ')).to eq('sunset')
      expect(described_class.normalise('Golden  Hour')).to eq('golden hour')
    end
  end

  describe 'validations' do
    it 'requires a label' do
      expect(build(:ai_tag_suggestion, label: nil)).not_to be_valid
    end

    # A confidence outside 0..1 means the gateway and the app disagree about
    # the scale, which would corrupt every threshold comparison.
    it 'rejects a confidence outside the unit range' do
      expect(build(:ai_tag_suggestion, confidence: 1.4)).not_to be_valid
      expect(build(:ai_tag_suggestion, confidence: -0.1)).not_to be_valid
    end

    # Absent confidence is not the same as zero confidence.
    it 'allows a missing confidence' do
      expect(build(:ai_tag_suggestion, confidence: nil)).to be_valid
    end

    it 'refuses two identical labels within one run' do
      suggestion = create(:ai_tag_suggestion, label: 'sunset')

      expect do
        create(:ai_tag_suggestion, ai_tagging_run: suggestion.ai_tagging_run, label: 'sunset')
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe '#accept!' do
    let(:asset) { create(:asset, properties: { 'tags' => [ 'existing' ] }) }
    let(:run) { create(:ai_tagging_run, asset: asset) }
    let(:user) { create(:user) }

    it 'copies the label onto the asset and records who decided' do
      suggestion = create(:ai_tag_suggestion, ai_tagging_run: run, asset: asset, label: 'sunset')

      suggestion.accept!(user: user)

      expect(asset.reload.properties['tags']).to contain_exactly('existing', 'sunset')
      expect(suggestion.state).to eq('accepted')
      expect(suggestion.decided_by).to eq(user)
      expect(suggestion.decided_at).to be_present
    end

    it 'preserves tags the asset already had' do
      suggestion = create(:ai_tag_suggestion, ai_tagging_run: run, asset: asset, label: 'sunset')

      suggestion.accept!(user: user)

      expect(asset.reload.properties['tags']).to include('existing')
    end

    it 'does not duplicate a tag the asset already carries' do
      suggestion = create(:ai_tag_suggestion, ai_tagging_run: run, asset: asset, label: 'existing')

      suggestion.accept!(user: user)

      expect(asset.reload.properties['tags']).to eq([ 'existing' ])
    end
  end

  describe '#dismiss!' do
    # A dismissal is about the machine's guess. If a person had separately
    # applied that tag themselves, that decision is theirs and stands.
    it 'does not remove the label from the asset' do
      asset = create(:asset, properties: { 'tags' => [ 'sunset' ] })
      run = create(:ai_tagging_run, asset: asset)
      suggestion = create(:ai_tag_suggestion, ai_tagging_run: run, asset: asset, label: 'sunset')

      suggestion.dismiss!(user: create(:user))

      expect(asset.reload.properties['tags']).to eq([ 'sunset' ])
      expect(suggestion.state).to eq('dismissed')
    end
  end
end
