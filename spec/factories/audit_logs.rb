FactoryBot.define do
  factory :audit_log do
    user { nil }
    action { "MyString" }
    auditable_type { "MyString" }
    auditable_id { 1 }
    changes_data { "" }
    ip_address { "MyString" }
    user_agent { "MyString" }
  end
end
