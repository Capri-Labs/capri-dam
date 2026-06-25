FactoryBot.define do
  factory :folder_policy do
    association :folder
    association :user_group

    read_access      { false }
    modify_access    { false }
    create_access    { false }
    delete_access    { false }
    replicate_access { false }
    manage_access    { false }
    explicit_deny    { false }

    trait :read_only do
      read_access { true }
    end

    trait :full_access do
      read_access      { true }
      modify_access    { true }
      create_access    { true }
      delete_access    { true }
      replicate_access { true }
      manage_access    { true }
    end

    trait :explicit_deny do
      explicit_deny { true }
    end
  end
end

