require "rails_helper"

RSpec.describe Admin::ReportsController, type: :controller do
  describe "private serialization helpers" do
    it "serializes nil timestamps without formatting them" do
      report = instance_double(
        ReportDefinition,
        id: 1,
        name: "Nil Timestamp Report",
        report_type: "custom_report",
        query_config: nil,
        active: true,
        created_at: nil,
        updated_at: nil
      )

      expect(controller.send(:serialize_report, report)).to include(
        description: nil,
        created_at: nil,
        updated_at: nil
      )
    end
  end
end
