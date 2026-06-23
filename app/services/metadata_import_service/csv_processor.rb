require "csv"

module MetadataImportService
  # Parses an uploaded metadata CSV, resolves each row to an Asset by its
  # absolute DAM path, updates the asset's metadata properties, and produces a
  # results CSV (original columns + status/message).
  class CsvProcessor
    Result = Struct.new(:csv_string, :total, :success, :failure, keyword_init: true)

    def initialize(import)
      @import     = import
      @path_col   = import.asset_path_column.to_s
      @ignored    = Array(import.ignored_columns).map(&:to_s).to_set
      @delimiter  = import.multi_value_delimiter.to_s
      @separator  = import.field_separator.presence || ","
      @batch_size = import.normalized_batch_size
    end

    # @return [Result]
    def process
      table   = CSV.parse(source_csv, headers: true, col_sep: @separator)
      headers = table.headers.compact
      lookup  = build_asset_lookup

      success = 0
      failure = 0
      rows    = []

      table.each_slice(@batch_size) do |batch|
        batch.each do |row|
          status, message = import_row(row, headers, lookup)
          success += 1 if status == "success"
          failure += 1 if status == "fail"
          rows << { row: row, status: status, message: message }
        end
      end

      Result.new(
        csv_string: build_results_csv(headers, rows),
        total:      rows.size,
        success:    success,
        failure:    failure
      )
    end

    private

    attr_reader :import

    def source_csv
      raise "Source file missing" unless import.source_file.attached?

      import.source_file.download
    end

    # ── Row import ────────────────────────────────────────────────────────────
    def import_row(row, headers, lookup)
      raw_path = row[@path_col]
      return ["fail", "Missing '#{@path_col}' value"] if raw_path.to_s.strip.empty?

      asset = lookup[normalize_path(raw_path)]
      return ["fail", "No asset found at path '#{raw_path}'"] unless asset

      properties = (asset.properties || {}).dup
      new_title  = nil

      headers.each do |column|
        next if column == @path_col
        next if @ignored.include?(column)

        value = row[column]
        # Empty value → leave the existing metadata untouched.
        next if value.nil? || value.to_s.strip.empty?

        if column.casecmp("title").zero?
          new_title = value.to_s
        else
          properties[column] = cast_value(value)
        end
      end

      attrs = { properties: properties, updated_at: Time.current }
      attrs[:title] = new_title if new_title.present?
      asset.update_columns(attrs)

      maybe_launch_workflow(asset)

      ["success", "Updated #{properties.keys.size} propert#{properties.keys.size == 1 ? 'y' : 'ies'}"]
    rescue StandardError => e
      ["fail", e.message]
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
      out_headers = headers + [MetadataImport::STATUS_COLUMN, MetadataImport::MESSAGE_COLUMN]
      CSV.generate(col_sep: @separator) do |csv|
        csv << out_headers
        rows.each do |entry|
          base = headers.map { |h| entry[:row][h] }
          csv << (base + [entry[:status], entry[:message]])
        end
      end
    end
  end
end



