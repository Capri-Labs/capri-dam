module Reports
  class Orchestrator
    def self.execute!(snapshot_id)
      snapshot = ReportSnapshot.find(snapshot_id)
      snapshot.processing!

      begin
        # 1. Data Fetching Phase
        # This delegates to a separate class that builds the SQL query based on parameters
        raw_data = Reports::DataFetcher.fetch(snapshot)

        # 2. Strategy Routing Phase
        # Dynamically instantiate the correct generator (e.g., Reports::Generators::Csv)
        generator_class = "Reports::Generators::#{snapshot.format.capitalize}".constantize
        generator = generator_class.new(raw_data, snapshot)

        # 3. Generation Phase
        file_io, filename, content_type = generator.generate

        # 4. Storage Phase
        snapshot.generated_file.attach(
          io: file_io,
          filename: filename,
          content_type: content_type
        )

        snapshot.completed!
      rescue => e
        # Catch any errors (memory limits, bad queries) and log them to the snapshot
        snapshot.update!(status: :failed, error_message: e.message)
        # Re-raise if you want your error monitoring (e.g., Sentry) to catch it
        raise e
      end
    end
  end
end
