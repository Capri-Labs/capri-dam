require "csv"

module Reports
  module Generators
    class Csv < Base
      def generate
        # Use a Ruby StringIO object to hold the file in memory before attaching
        csv_string = CSV.generate do |csv|
          # Add Headers
          csv << data.first.keys if data.any?

          # Add Rows
          data.each do |row|
            csv << row.values
          end
        end

        io = StringIO.new(csv_string)
        filename = default_filename("csv")

        [ io, filename, "text/csv" ]
      end
    end
  end
end
