class CreateDailyMetrics < ActiveRecord::Migration[7.0]
  def change
    create_table :daily_metrics do |t|
      t.date :metric_date, null: false
      t.string :metric_name, null: false
      t.integer :metric_value, default: 0
      t.jsonb :metadata, default: {}
      t.timestamps
    end
    add_index :daily_metrics, [:metric_date, :metric_name], unique: true
  end
end