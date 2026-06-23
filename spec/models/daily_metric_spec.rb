require 'rails_helper'

RSpec.describe DailyMetric, type: :model do
  describe 'factory' do
    it 'is a valid ActiveRecord model' do
      expect(DailyMetric).to respond_to(:all)
    end
  end

  describe 'table access' do
    it 'can be queried' do
      expect { DailyMetric.count }.not_to raise_error
    end
  end
end
