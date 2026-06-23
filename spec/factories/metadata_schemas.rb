FactoryBot.define do
  factory :metadata_schema do
    sequence(:name)  { |n| "Schema #{n}" }
    sequence(:slug)  { |n| "schema-#{n}" }
    description      { "A test metadata schema" }
    level            { "root" }
    mime_segment     { nil }
    is_builtin       { false }
    tabs             { [] }
    properties       { {} }
    deleted_at       { nil }

    trait :builtin do
      is_builtin { true }
    end

    trait :root do
      level        { "root" }
      parent       { nil }
      mime_segment { nil }
    end

    trait :type_level do
      level        { "type" }
      mime_segment { "image" }
      association :parent, factory: :metadata_schema, strategy: :create
    end

    trait :subtype_level do
      level        { "subtype" }
      mime_segment { "jpeg" }
      association :parent, factory: [:metadata_schema, :type_level], strategy: :create
    end

    trait :with_basic_tab do
      tabs do
        [{
          "id"       => SecureRandom.uuid,
          "name"     => "Basic",
          "position" => 0,
          "fields"   => [
            {
              "id"              => SecureRandom.uuid,
              "field_type"      => "text",
              "label"           => "Title",
              "map_to_property" => "dc:title",
              "position"        => 0,
              "required"        => true,
              "read_only"       => false,
              "rules"           => {}
            }
          ]
        }]
      end
    end
  end
end

