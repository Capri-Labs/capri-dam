every 1.day, at: '1:00 am' do
  runner "Metrics::Aggregator.run_daily_snapshot!"
end