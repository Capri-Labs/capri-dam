require "csv"

module MetadataImportService
  # Parses an uploaded metadata CSV, resolves each row to an Asset by its
  # absolute DAM path, updates the asset's metadata properties, and produces a
  # results CSV (original columns + status/message).
  class CsvProcessor
    Result = Struct.new(:csv_string, :total, :success, :failure, :rows, keyword_init: true)
    RowResult = Struct.new(
      :row_number,
      :asset_path,
      :resolved_asset_path,
      :status,
      :message,
      :changes,
      keyword_init: true
    )

    def initialize(import, dry_run: false, source_csv: nil)
      @import      = import
      @dry_run     = dry_run
      @provided_csv = source_csv
      @path_col    = import.asset_path_column.to_s
      @ignored     = Array(import.ignored_columns).map(&:to_s).to_set
      @delimiter   = import.multi_value_delimiter.to_s
      @separator   = import.field_separator.presence || ","
      @batch_size  = import.normalized_batch_size
    end

    # @return [Result]
    def process
      table   = CSV.parse(source_csv, headers: true, col_sep: @separator)
      headers = table.headers.compact
      lookup  = build_asset_lookup

      success      = 0
      failure      = 0
      preview_rows = []
      csv_rows     = []
      row_number   = 1

      table.each_slice(@batch_size) do |batch|
        batch.each do |row|
          row_number += 1
          result = import_row(row, headers, lookup, row_number: row_number)
          success += 1 if result.status == "success"
          failure += 1 if result.status == "fail"
          preview_rows << result
          csv_rows << { row: row, status: result.status, message: result.message }
        end
      end

      Result.new(
        csv_string: build_results_csv(headers, csv_rows),
        total:      preview_rows.size,
        success:    success,
        failure:    failure,
        rows:       preview_rows
      )
    end

    private

    attr_reader :import

    def source_csv
      return @provided_csv unless @provided_csv.nil?

      raise "Source file missing" unless import.source_file.attached?

      import.source_file.download
    end

    def dry_run?
      @dry_run
    end

    # ── Row import ────────────────────────────────────────────────────────────
    def import_row(row, headers, lookup, row_number:)
      raw_path = row[@path_col]
      if raw_path.to_s.strip.empty?
        return failure_result(row_number, raw_path, nil, "Missing '#{@path_col}' value")
      end

      normalized_path = normalize_path(raw_path)
      asset = lookup[normalized_path]
      return failure_result(row_number, raw_path, normalized_path, "No asset found at path '#{raw_path}'") unless asset

      attrs, changes = build_attributes_and_changes(asset, row, headers)
      persist_changes(asset, attrs) unless dry_run?
      maybe_launch_workflow(asset) unless dry_run?

      success_result(row_number, raw_path, normalized_path, changes)
    rescue StandardError => e
      failure_result(row_number, raw_path, normalized_path, e.message)
    end

    def build_attributes_and_changes(asset, row, headers)
      properties = (asset.properties || {}).deep_dup
      attrs      = {}
      changes    = []

      headers.each do |column|
        next if column == @path_col
        next if @ignored.include?(column)

        value = row[column]
        next if value.nil? || value.to_s.strip.empty?

        if column.casecmp("title").zero?
          new_title = value.to_s
          next if asset.title == new_title

          attrs[:title] = new_title
          changes << build_change("title", asset.title, new_title)
        else
          casted_value = cast_value(value)
          next if properties[column] == casted_value

          changes << build_change(column, properties[column], casted_value)
          properties[column] = casted_value
          attrs[:properties] = properties
        end
      end

      [ attrs, changes ]
    end

    def persist_changes(asset, attrs)
      asset.update_columns(attrs.merge(updated_at: Time.current))
    end

    def success_result(row_number, raw_path, normalized_path, changes)
      RowResult.new(
        row_number:          row_number,
        asset_path:          raw_path.to_s,
        resolved_asset_path: normalized_path,
        status:              "success",
        message:             success_message(changes),
        changes:             changes
      )
    end

    def failure_result(row_number, raw_path, normalized_path, message)
      RowResult.new(
        row_number:          row_number,
        asset_path:          raw_path.to_s,
        resolved_asset_path: normalized_path,
        status:              "fail",
        message:             message,
        changes:             []
      )
    end

    def build_change(field, from_value, to_value)
      {
        field: field,
        from:  from_value,
        to:    to_value,
      }
    end

    def success_message(changes)
      return "No changes required" if changes.empty?

      property_changes = changes.count { |change| change[:field] != "title" }
      title_changed    = changes.any? { |change| change[:field] == "title" }

      return "Updated title" if property_changes.zero? && title_changed

      "Updated #{property_changes} propert#{property_changes == 1 ? "y" : "ies"}"
    end

    # Split multi-value cells into arrays; keep single values scalar.
    def cast_value(value)
      str = value.to_s
      return str if @delimiter.empty? || !str.include?(@delimiter)

      str.split(@delimiter).map(&:strip).reject(&:empty?)
    end

    # Optional DAM Metadata WriteBack workflow hook. Disabled by default since
    # enabling workflows slows the system down.
    def maybe_launch_workflow(asset)
      return unless import.launch_workflows

      Rails.logger.info("[MetadataImport ##{import.id}] WriteBack workflow launch for asset #{asset.id}")
      # Hook point: enqueue the DAM Metadata WriteBack workflow here when configured.
    end

    # ── Asset path lookup ─────────────────────────────────────────────────────
    # Maps a normalized absolute path ("/folder/sub/title") to its Asset.
    def build_asset_lookup
      folder_paths = folder_path_lookup
      map = {}
      Asset.active.includes(:folder).find_each do |asset|
        base = asset.folder_id ? folder_paths[asset.folder_id] : ""
        path = normalize_path("#{base}/#{asset.title}")
        map[path] ||= asset
      end
      map
    end

    # Case-sensitive, but tolerant of leading/trailing slashes and doubles.
    def normalize_path(path)
      cleaned = path.to_s.strip.gsub(%r{/+}, "/").sub(%r{/\z}, "")
      cleaned = "/#{cleaned}" unless cleaned.start_with?("/")
      cleaned
    end

    # folder_id => "/Marketing/2026/Campaigns"
    def folder_path_lookup
      @folder_path_lookup ||= begin
        all = Folder.active.to_a.index_by(&:id)
        all.each_with_object({}) do |(id, folder), memo|
          names = []
          current = folder
          while current
            names.unshift(current.name)
            current = all[current.parent_id]
          end
          memo[id] = "/" + names.join("/")
        end
      end
    end

    # ── Results CSV ───────────────────────────────────────────────────────────
    def build_results_csv(headers, rows)
      out_headers = headers + [ MetadataImport::STATUS_COLUMN, MetadataImport::MESSAGE_COLUMN ]
      CSV.generate(col_sep: @separator) do |csv|
        csv << out_headers
        rows.each do |entry|
          base = headers.map { |header| entry[:row][header] }
          csv << (base + [ entry[:status], entry[:message] ])
        end
      end
    end
  end
end
