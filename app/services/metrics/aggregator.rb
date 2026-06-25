module Metrics
  class Aggregator
    def self.run_daily_snapshot!(date = Date.yesterday)
      # 1. Total Assets Created
      count = Asset.where(created_at: date.all_day).count
      DailyMetric.find_or_create_by!(metric_date: date, metric_name: "assets_created")
                 .update!(metric_value: count)

      # 2. Workflow Throughput
      throughput = WorkflowTask.where(completed_at: date.all_day).count
      DailyMetric.find_or_create_by!(metric_date: date, metric_name: "workflows_completed")
                 .update!(metric_value: throughput)

      # 3. Active Users
      active_users = User.where(last_login_at: date.all_day).count
      DailyMetric.find_or_create_by!(metric_date: date, metric_name: "active_users")
                 .update!(metric_value: active_users)
    end
  end
end
