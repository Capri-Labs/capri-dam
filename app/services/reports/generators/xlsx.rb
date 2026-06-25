require "axlsx"

module Reports
  module Generators
    class Xlsx < Base
      def generate
        package = Axlsx::Package.new
        workbook = package.workbook

        # Define styles
        workbook.styles do |s|
          # Enterprise Header Style: Bold, dark text on a light gray background with a thin bottom border
          header_style = s.add_style(
            b: true,
            bg_color: "F8F9FA",
            fg_color: "1E293B",
            border: { style: :thin, color: "E2E8F0", edges: [ :bottom ] },
            alignment: { horizontal: :left, vertical: :center }
          )

          # Standard Data Row Style
          data_style = s.add_style(
            alignment: { horizontal: :left, vertical: :center }
          )

          # Truncate the sheet name if it exceeds Excel's 31 character limit
          sheet_name = snapshot.report_definition.name.truncate(31, omission: "")

          workbook.add_worksheet(name: sheet_name) do |sheet|
            if data.any?
              # 1. Extract Headers
              headers = data.first.keys.map { |k| k.to_s.titleize }
              sheet.add_row headers, style: header_style, height: 25

              # 2. Extract and append Rows
              data.each do |row|
                sheet.add_row row.values, style: data_style
              end

              # 3. Apply UX Enhancements
              # Freeze the top header row so it stays visible while scrolling
              sheet.sheet_view.pane do |pane|
                pane.state = :frozen
                pane.y_split = 1
              end

              # Add auto-filters to all columns in the header row
              # 'A1' to the last column letter + '1'
              last_column_letter = Axlsx.col_ref(headers.length - 1)
              sheet.auto_filter = "A1:#{last_column_letter}1"
            else
              # Fallback for empty datasets
              sheet.add_row [ "No data available for the selected parameters." ], style: data_style
            end
          end
        end

        # package.to_stream returns a StringIO object natively
        io = package.to_stream
        filename = default_filename("xlsx")
        mime_type = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"

        [ io, filename, mime_type ]
      end
    end
  end
end
