class CreateReportDefinitions < ActiveRecord::Migration[8.1]
  def change
    create_table :report_definitions do |t|
      t.string :name
      t.string :report_type
      t.jsonb :query_config
      t.boolean :active

      t.timestamps
    end
  end
end
