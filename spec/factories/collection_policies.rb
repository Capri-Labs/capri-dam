FactoryBot.define do
  factory :collection_policy do
    association :collection
    association :user_group

    view_access   { false }
    edit_access   { false }
    admin_access  { false }
    explicit_deny { false }

    trait :viewer do
      view_access { true }
    end

    trait :editor do
      view_access { true }
      edit_access { true }
    end

    trait :collection_admin do
      view_access  { true }
      edit_access  { true }
      admin_access { true }
    end

    trait :explicit_deny do
      explicit_deny { true }
    end
  end
end
