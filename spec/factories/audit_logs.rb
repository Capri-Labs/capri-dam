FactoryBot.define do
  factory :audit_log do
    association :user
    action         { "update" }
    auditable_type { "Asset" }
    auditable_id   { 1 }
    changes_data   { { "title" => [ "old", "new" ] } }
    ip_address     { "127.0.0.1" }
    user_agent     { "RSpec" }
    impersonated   { false }
    true_user      { nil }
  end
end
