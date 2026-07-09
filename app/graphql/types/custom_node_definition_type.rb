module Types
  class CustomNodeDefinitionType < Types::BaseObject
    description "A declarative custom workflow node manifest registered by an administrator."

    field :id, ID, null: false
    field :key, String, null: false
    field :node_type, String, null: false, description: "Workflow node type in plugin:<key> form."
    field :name, String, null: false
    field :description, String, null: true
    field :icon, String, null: true
    field :category, String, null: false
    field :color, String, null: false
    field :config_schema, Types::JsonType, null: false
    field :runtime, Types::JsonType, null: false, description: "Runtime config with secrets stripped."
    field :status, String, null: false
    field :failure_count, Integer, null: false
    field :last_error, String, null: true
    field :last_dispatched_at, GraphQL::Types::ISO8601DateTime, null: true
    field :circuit_open, Boolean, null: false
    field :created_by, String, null: true
    field :created_at, GraphQL::Types::ISO8601DateTime, null: false
    field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

    def runtime
      (object.runtime || {}).deep_dup.reject { |key, _value| key.to_s.match?(/secret|token|password|credential|api[_-]?key/i) }
    end


    def circuit_open
      object.circuit_open?
    end

    def created_by
      object.created_by&.email
    end

    def self.authorized?(object, context)
      super && context[:current_user]&.admin?
    end
  end
end
