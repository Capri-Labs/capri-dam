# frozen_string_literal: true

module Types
  # GraphQL type for an AI-assisted bin cleanup suggestion.
  #
  # The +ai*+ fields are placeholders that will be populated by the Capri AI
  # Gateway (https://github.com/Capri-Labs/capri-dam-ai-gateway) once wired up.
  # Until then +heuristicScore+ provides a rule-based ranking.
  class BinAiSuggestionType < Types::BaseObject
    description "An AI-assisted suggestion for permanently purging a trashed asset."

    field :id,                 ID,      null: false
    field :title,              String,  null: true
    field :deleted_at,         GraphQL::Types::ISO8601DateTime, null: true
    field :age_days,           Integer, null: false
    field :size_bytes,         Integer, null: false
    field :size_human,         String,  null: true
    field :has_collection_pin, Boolean, null: false,
          description: "True when the asset is still referenced by a collection."
    field :has_active_workflow, Boolean, null: false,
          description: "True when the asset has an in-progress workflow (protects it from purge)."
    field :heuristic_score,    Integer, null: false,
          description: "Rule-based 0–100 score; higher = safer to delete (used until AI gateway is live)."

    # ── AI gateway fields (null until integrated) ──────────────────────────────
    field :ai_risk_score, Integer, null: true,
          description: "AI confidence (0–100) that the asset is safe to delete. Null until gateway live."
    field :ai_reason,     String, null: true,
          description: "Human-readable LLM explanation. Null until gateway live."
    field :ai_tags,       [ String ], null: false,
          description: "Semantic tags inferred from asset content. Empty until gateway live."
  end
end
