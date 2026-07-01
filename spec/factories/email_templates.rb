FactoryBot.define do
  factory :email_template do
    sequence(:name) { |n| "Template #{n}" }
    sequence(:event_trigger) { |n| "asset.created.#{n}" }
    subject { 'Asset notification' }
    html_body { '<p>Hello {{name}}</p>' }
    text_body { 'Hello {{name}}' }
    active { true }
  end
end
