class CreateReportSnapshots < ActiveRecord::Migration[7.0]
  def change
    create_table :report_snapshots do |t|
      t.references :report_definition, null: false, foreign_key: true
      t.integer :status, default: 0
      t.string :format, null: false
      t.jsonb :parameters, default: {}
      t.text :error_message

      t.timestamps
    end
  end
end