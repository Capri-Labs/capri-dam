# frozen_string_literal: true

module Types
  class C2paConfigurationType < Types::BaseObject
    description "Organisation-wide C2PA / Content Provenance policy configuration."

    field :id,                      ID,      null: false
    field :gateway_c2pa_enabled,    Boolean, null: false
    field :auto_verify_on_ingest,   Boolean, null: false
    field :auto_sign_on_ingest,     Boolean, null: false
    field :require_c2pa_on_import,  Boolean, null: false
    field :ai_disclosure_required,  Boolean, null: false
    field :signing_issuer_name,     String,  null: true
    field :signing_org,             String,  null: true
    field :trust_store_urls,        [ String ], null: false
    field :verification_strictness, String,  null: false, description: "lenient | strict"
    field :policy_notes,            String,  null: true
    field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

    def self.authorized?(_object, context)
      super && context[:current_user]&.admin?
    end
  end
end
