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
