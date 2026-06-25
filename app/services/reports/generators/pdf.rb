require "prawn"
require "prawn/table"

module Reports
  module Generators
    class Pdf < Base
      def generate
        # Initialize a landscape document for wider data tables
        pdf = Prawn::Document.new(page_layout: :landscape, margin: 40)

        build_header(pdf)
        build_table(pdf)
        build_footer(pdf)

        # Prawn's #render method returns the raw PDF binary string.
        # We wrap it in a StringIO object so ActiveStorage can attach it.
        io = StringIO.new(pdf.render)
        filename = default_filename("pdf")

        [ io, filename, "application/pdf" ]
      end

      private

      def build_header(pdf)
        # Title dynamically pulled from the definition
        pdf.text snapshot.report_definition.name, size: 20, style: :bold, color: "121926"
        pdf.move_down 5

        # Subtitle with timestamp and parameters context
        pdf.text "Generated on: #{Time.current.strftime("%B %d, %Y at %H:%M")}", size: 10, color: "64748b"

        if snapshot.parameters.any?
          params_text = snapshot.parameters.map { |k, v| "#{k.titleize}: #{v}" }.join(" | ")
          pdf.text "Filters: #{params_text}", size: 10, color: "64748b"
        end

        pdf.move_down 20
      end

      def build_table(pdf)
        if data.empty?
          pdf.text "No data available for the selected parameters.", style: :italic, color: "64748b"
          return
        end

        # 1. Extract Headers (Capitalizing the hash keys)
        headers = data.first.keys.map { |k| k.to_s.titleize }

        # 2. Extract Rows
        rows = data.map(&:values)

        # 3. Combine for prawn-table
        table_data = [ headers ] + rows

        # 4. Render with strict styling
        pdf.table(table_data, header: true, width: pdf.bounds.width) do |t|
          # Header Row Styling
          t.row(0).font_style = :bold
          t.row(0).background_color = "f8f9fa"
          t.row(0).text_color = "1e293b"

          # Global Cell Styling
          t.cells.padding = [ 8, 10 ]
          t.cells.border_width = 0.5
          t.cells.border_color = "e2e8f0"
          t.cells.size = 10

          # Alternating Row Colors for readability
          t.cells.style do |c|
            if c.row > 0 # Skip header
              c.background_color = (c.row % 2).zero? ? "ffffff" : "fbfcfe"
            end
          end
        end
      end

      def build_footer(pdf)
        # Adds "Page X of Y" to the bottom right of every page
        pdf.number_pages "Page <page> of <total>",
                         at: [ pdf.bounds.right - 150, 0 ],
                         width: 150,
                         align: :right,
                         size: 9,
                         color: "94a3b8"
      end
    end
  end
end
