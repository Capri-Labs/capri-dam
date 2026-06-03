class CreateAiConfigurations < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_configurations do |t|
      t.string :active_provider
      t.string :generation_model
      t.string :embedding_model
      t.decimal :monthly_budget_usd
      t.decimal :current_spend_usd
      t.text :system_prompt
      t.boolean :fallback_to_local

      t.timestamps
    end
  end
end
