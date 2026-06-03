class CreateAssetEmbeddings < ActiveRecord::Migration[8.1]
  def change
    # 1. Enable the pgvector extension in PostgreSQL
    enable_extension "vector"

    # 2. Create the decoupled embeddings table using UUIDs
    create_table :asset_embeddings, id: :uuid do |t|
      # Explicitly link to the Asset table using UUID
      t.references :asset, type: :uuid, null: false, foreign_key: true, index: { unique: true }

      # Limit set to 1536 dimensions (the standard for models like OpenAI text-embedding-3-small)
      t.vector :embedding, limit: 1536, null: false

      # Tracking the model name prevents technical debt by allowing clear version mapping
      # if you later upgrade to a different embedding provider
      t.string :model_name, null: false

      t.timestamps
    end

    # 3. Add an HNSW index using cosine distance calculation for high-performance semantic search
    add_index :asset_embeddings, :embedding, using: :hnsw, opclass: :vector_cosine_ops
  end
end