module Types
  class JsonType < Types::BaseScalar
    description "A universally flexible JSON string or structure for dynamic asset metadata properties."

    def self.coerce_input(input_value, context)
      input_value # Pass straight through to ActiveRecord JSONB
    end

    def self.coerce_result(output_value, context)
      output_value
    end
  end
end