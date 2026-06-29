# frozen_string_literal: true

# Adds the analysis_report JSONB column to system_connectors.
# This column is written by PreFlightAnalysisWorker and read by the
# Connector Health tab in the Data Health dashboard.
class AddAnalysisReportToSystemConnectors < ActiveRecord::Migration[8.1]
  def change
    add_column :system_connectors, :analysis_report, :jsonb, default: nil
  end
end
