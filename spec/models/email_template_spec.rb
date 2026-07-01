require 'rails_helper'

RSpec.describe EmailTemplate, type: :model do
  subject(:email_template) { create(:email_template) }

  describe 'associations' do
    it { is_expected.to have_many(:email_deliveries).dependent(:nullify) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:subject) }
    it { is_expected.to validate_presence_of(:event_trigger) }
    it { is_expected.to validate_inclusion_of(:active).in_array([ true, false ]) }
    it { is_expected.to validate_uniqueness_of(:event_trigger) }
  end

  describe 'scopes' do
    let!(:active_template) { create(:email_template, active: true) }
    let!(:inactive_template) { create(:email_template, active: false) }

    it '.active returns active templates only' do
      expect(described_class.active).to include(active_template)
      expect(described_class.active).not_to include(inactive_template)
    end
  end
end
