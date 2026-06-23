FactoryBot.define do
  factory :collection_asset do
    association :collection
    association :asset
  end
end
