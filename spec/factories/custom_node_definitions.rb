FactoryBot.define do
  factory :custom_node_definition do
    sequence(:key) { |n| "acme_node_#{n}" }
    name { "Acme Custom Node" }
    description { "Calls a tenant-hosted workflow node endpoint." }
    icon { "extension" }
    category { "custom" }
    color { "#6366f1" }
    config_schema do
      [
        { "key" => "quality", "type" => "string", "label" => "Quality" },
      ]
    end
    runtime do
      {
        "endpoint_url" => "https://plugins.example.com/workflow/custom-node",
        "timeout_ms" => 5000,
        "outputs" => [ "approved", "rejected" ],
        "secret" => "test-secret",
      }
    end
    status { "enabled" }
    association :created_by, factory: [ :user, :admin ]

    trait :draft do
      status { "draft" }
    end

    trait :disabled do
      status { "disabled" }
    end
  end
end
