require 'rails_helper'

RSpec.describe Ai::TagSuggestionImporter do
  let(:asset) { create(:asset, properties: { 'tags' => [ 'existing' ] }) }
  let(:run)   { create(:ai_tagging_run, :running, asset: asset) }

  def import(labels)
    described_class.new(run).import(labels)
  end

  it 'creates pending suggestions and completes the run' do
    result = import([
      { 'label' => 'sunset', 'confidence' => 0.91 },
      { 'label' => 'beach',  'confidence' => 0.82 },
    ])

    expect(result.imported).to eq(2)
    expect(run.reload.status).to eq('completed')
    expect(run.suggestions_count).to eq(2)
    expect(AiTagSuggestion.pending.pluck(:label)).to contain_exactly('sunset', 'beach')
  end

  # The whole point of the feature: the pipeline proposes, it does not assert.
  it 'never writes to the asset tags' do
    import([ { 'label' => 'sunset', 'confidence' => 0.99 } ])

    expect(asset.reload.properties['tags']).to eq([ 'existing' ])
  end

  it 'normalises labels' do
    import([ { 'label' => '  Golden  Hour ', 'confidence' => 0.9 } ])

    expect(AiTagSuggestion.last.label).to eq('golden hour')
  end

  describe 'what it throws away' do
    # A model unsure of what it saw produces triage fatigue.
    it 'drops labels below the confidence floor' do
      result = import([
        { 'label' => 'sunset', 'confidence' => 0.9 },
        { 'label' => 'maybe',  'confidence' => 0.1 },
      ])

      expect(result.imported).to eq(1)
      expect(result.skipped).to eq(1)
      expect(AiTagSuggestion.pluck(:label)).to eq([ 'sunset' ])
    end

    # Asking someone to agree with a tag they already applied is noise.
    it 'drops labels the asset already carries, case-insensitively' do
      result = import([ { 'label' => 'Existing', 'confidence' => 0.95 } ])

      expect(result.imported).to eq(0)
      expect(result.skipped).to eq(1)
    end

    # A rejection is a decision; re-proposing would make it meaningless and
    # the queue self-refilling.
    it 'drops labels dismissed on a previous run' do
      previous = create(:ai_tagging_run, asset: asset)
      create(:ai_tag_suggestion, :dismissed, ai_tagging_run: previous, asset: asset, label: 'blurry')

      result = import([ { 'label' => 'blurry', 'confidence' => 0.99 } ])

      expect(result.imported).to eq(0)
      expect(AiTagSuggestion.pending).to be_empty
    end

    it 'drops duplicates within a single payload' do
      result = import([
        { 'label' => 'sunset', 'confidence' => 0.9 },
        { 'label' => 'Sunset', 'confidence' => 0.8 },
      ])

      expect(result.imported).to eq(1)
      expect(result.skipped).to eq(1)
    end

    it 'drops blank and over-long labels' do
      result = import([
        { 'label' => '',            'confidence' => 0.9 },
        { 'label' => 'x' * 200,     'confidence' => 0.9 },
      ])

      expect(result.imported).to eq(0)
      expect(result.skipped).to eq(2)
    end
  end

  # A chatty model must not be able to bury a person in labels.
  it 'caps the number of suggestions however many arrive' do
    labels = 60.times.map { |i| { 'label' => "tag#{i}", 'confidence' => 0.9 } }

    result = import(labels)

    expect(result.imported).to eq(AiTaggingRun::MAX_SUGGESTIONS)
    expect(AiTagSuggestion.count).to eq(AiTaggingRun::MAX_SUGGESTIONS)
  end

  describe 'untrusted input' do
    # A gateway reporting 1.4 has a scaling bug, but the label it found is
    # probably still real.
    it 'clamps an out-of-range confidence rather than discarding the label' do
      import([ { 'label' => 'sunset', 'confidence' => 1.4 } ])

      expect(AiTagSuggestion.last.confidence).to eq(1.0)
    end

    it 'keeps a label whose confidence is unparseable, with no confidence' do
      import([ { 'label' => 'sunset', 'confidence' => 'very sure' } ])

      expect(AiTagSuggestion.last.label).to eq('sunset')
      expect(AiTagSuggestion.last.confidence).to be_nil
    end

    it 'accepts a bare string label' do
      import([ 'sunset' ])

      expect(AiTagSuggestion.last.label).to eq('sunset')
    end

    it 'tolerates an empty or nil payload' do
      expect { import(nil) }.not_to raise_error
      expect(run.reload.status).to eq('completed')
      expect(run.suggestions_count).to eq(0)
    end
  end
end
