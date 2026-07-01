class EnhanceEmailTemplates < ActiveRecord::Migration[8.1]
  def change
    add_column :email_templates, :description, :text
    add_column :email_templates, :category, :string, default: "transactional", null: false
    add_column :email_templates, :variables, :jsonb, default: {}, null: false
    add_column :email_templates, :preview_data, :jsonb, default: {}, null: false
    add_reference :email_templates, :created_by, foreign_key: { to_table: :users }, type: :bigint

    add_index :email_templates, :category
  end
end
