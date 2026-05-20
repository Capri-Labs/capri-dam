class AddExtendedFieldsToWorkflows < ActiveRecord::Migration[8.1]
  def change
    add_column :workflows, :fallback_assignee_type, :string
    add_column :workflows, :fallback_assignee_id, :string
  end
end
