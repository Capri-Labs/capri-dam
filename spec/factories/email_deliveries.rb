FactoryBot.define do
  factory :email_delivery do
    association :email_template
    sequence(:recipient_email) { |n| "recipient_#{n}@example.com" }
    payload { { 'name' => 'Test User' } }
    retry_count { 0 }
    status { 'pending' }
    error_log { nil }
  end
end
