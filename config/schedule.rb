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

# Applies due "Publish Later"/"Unpublish Later" requests (ScheduledPublishAction).
# Polling (rather than perform_at/perform_in per-request) means a schedule that
# was missed while the app was down still runs on the very next tick.
every 5.minutes do
  runner "PublishSchedulerWorker.perform_async"
end

# Nightly integrity audit. Verifies a budgeted, staleness-ordered slice of the
# estate rather than everything: a full sweep means downloading every object,
# which on remote storage is an egress bill that gets the whole audit switched
# off after the first invoice. Runs at 4am, after the other nightly jobs, so it
# is competing for storage bandwidth with as little else as possible.
every 1.day, at: "4:00 am" do
  runner "FixityAuditWorker.perform_async"
end
