class CreateCollectionRules < ActiveRecord::Migration[7.0]
  def change
    create_table :collection_rules do |t|
      t.references :collection, null: false, foreign_key: true

      # The human-readable NLP prompt (e.g., "High-resolution outdoor lifestyle shots involving snow")
      t.text :semantic_prompt, null: false

      # The cosine similarity threshold (e.g., 0.85). Stored as decimal for precision.
      t.decimal :similarity_threshold, precision: 4, scale: 3, default: 0.800

      # Strict structural guardrails (e.g., { "status": "approved", "orientation": "landscape" })
      t.jsonb :metadata_filters, default: {}

      # Toggle to pause the pipeline without deleting the rule
      t.boolean :active, default: true, null: false

      t.timestamps
    end

    # Index for fast JSONB querying during ingestion intercepts
    add_index :collection_rules, :metadata_filters, using: :gin
  end
end