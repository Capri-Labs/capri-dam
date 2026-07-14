every 1.day, at: "1:00 am" do
  runner "Metrics::Aggregator.run_daily_snapshot!"
end

# Purge metadata export CSVs that are older than 30 days.
every 1.day, at: "2:00 am" do
  runner "MetadataExportCleanupWorker.perform_async"
end

# Purge metadata import artifacts (source + results CSVs) older than 30 days.
every 1.day, at: "2:15 am" do
  runner "MetadataImportCleanupWorker.perform_async"
end

# Purge bulk asset/folder ZIP downloads older than 7 days.
every 1.day, at: "2:30 am" do
  runner "AssetDownloadCleanupWorker.perform_async"
end

# Enterprise Recycle Bin purge — permanently destroys expired trashed items.
# Policy (retention_days, workflow_behavior, etc.) is configurable via
# GET/PUT /api/v1/bin/retention_policy.
every 1.day, at: "3:00 am" do
  runner "BinPurgeWorker.perform_async"
end

# Keeps Adobe IMS (AEM) service-account access tokens fresh so scheduled/
# in-flight migrations never stall on an expired token.
every 10.minutes do
  runner "AemTokenRefreshWorker.perform_async"
end
