module Reports
  class Orchestrator
    def self.execute!(snapshot_id)
      snapshot = ReportSnapshot.find(snapshot_id)

      begin
        snapshot.processing!

        # 1. Data Fetching Phase
        raw_data = Reports::DataFetcher.fetch(snapshot)

        # 2. Strategy Routing Phase — explicit case avoids unsafe constantize / const_get.
        generator_class = case snapshot.format.to_s.downcase
        when "csv"  then Reports::Generators::Csv
        when "xlsx" then Reports::Generators::Xlsx
        when "pdf"  then Reports::Generators::Pdf
        else raise ArgumentError, "Unsupported report format: #{snapshot.format}"
        end
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
        snapshot.update_columns(
          status: ReportSnapshot.statuses[:failed],
          error_message: e.message,
          updated_at: Time.current
        )
        # Re-raise if you want your error monitoring (e.g., Sentry) to catch it
        raise e
      end
    end
  end
end
