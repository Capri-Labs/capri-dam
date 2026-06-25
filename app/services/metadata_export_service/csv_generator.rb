require "csv"

module MetadataExportService
  # Traverses a folder hierarchy, reads each asset's metadata `properties`
  # and renders one or more CSV files (split at MetadataExport::MAX_ROWS_PER_FILE).
  class CsvGenerator
    # Fixed leading columns that are always present in the export.
    BASE_COLUMNS = %w[asset_id title folder_path status created_at].freeze

    Result = Struct.new(:filename, :content_type, :data, keyword_init: true)

    def initialize(export)
      @export = export
    end

    # Returns an Array of Result structs (one per generated CSV file) and the
    # total number of assets processed.
    #
    # @return [Array(Array<Result>, Integer)]
    def generate
      asset_ids = collect_asset_ids
      total     = asset_ids.size
      columns   = BASE_COLUMNS + property_columns(asset_ids)

      files = []
      slices = asset_ids.each_slice(MetadataExport::MAX_ROWS_PER_FILE).to_a
      slices.each_with_index do |slice, index|
        files << build_csv(slice, columns, index, slices.size)
      end

      # Always emit at least an (empty) file so the user has something to download.
      files << build_csv([], columns, 0, 1) if files.empty?

      [ files, total ]
    end

    private

    attr_reader :export

    # ── Asset collection ─────────────────────────────────────────────────────
    def collect_asset_ids
      folder_ids = target_folder_ids
      scope =
        if export.folder_id.blank?
          # Root export: assets with no folder (+ everything when cascading).
          export.include_subfolders ? Asset.active : Asset.active.where(folder_id: nil)
        else
          Asset.active.where(folder_id: folder_ids)
        end

      scope.order(:created_at).pluck(:id)
    end

    # Resolve the folder + (optionally) all descendant folder ids.
    def target_folder_ids
      return [] if export.folder_id.blank?

      ids = [ export.folder_id ]
      return ids unless export.include_subfolders

      queue = [ export.folder_id ]
      until queue.empty?
        children = Folder.active.where(parent_id: queue).pluck(:id)
        new_ids  = children - ids
        ids.concat(new_ids)
        queue = new_ids
      end
      ids
    end

    # ── Column resolution ────────────────────────────────────────────────────
    def property_columns(asset_ids)
      if export.selective?
        Array(export.selected_properties).map(&:to_s).reject(&:blank?).uniq
      else
        discover_all_keys(asset_ids)
      end
    end

    # Build the union of every property key across the exported assets.
    def discover_all_keys(asset_ids)
      keys = []
      asset_ids.each_slice(1_000) do |batch|
        Asset.where(id: batch).pluck(:properties).each do |props|
          next unless props.is_a?(Hash)

          props.keys.each { |k| keys << k.to_s }
        end
      end
      keys.uniq.sort
    end

    # ── CSV rendering ────────────────────────────────────────────────────────
    def build_csv(asset_ids, columns, part_index, total_files)
      folder_paths = folder_path_lookup

      csv_string = CSV.generate do |csv|
        csv << columns
        Asset.where(id: asset_ids).includes(:folder).find_each do |asset|
          csv << row_for(asset, columns, folder_paths)
        end
      end

      Result.new(
        filename:     filename_for(part_index, total_files),
        content_type: "text/csv",
        data:         csv_string
      )
    end

    def row_for(asset, columns, folder_paths)
      props = asset.properties || {}
      columns.map do |col|
        case col
        when "asset_id"    then asset.id
        when "title"       then asset.title
        when "folder_path" then folder_paths[asset.folder_id] || "/"
        when "status"      then asset.status
        when "created_at"  then asset.created_at&.iso8601
        else flatten_value(props[col] || props[col.to_sym])
        end
      end
    end

    def flatten_value(value)
      case value
      when Array then value.join("; ")
      when Hash  then value.to_json
      else value
      end
    end

    def filename_for(part_index, total_files)
      base = export.name.to_s.gsub(/\.csv\z/i, "").gsub(/[^\w\-]+/, "_")
      base = "metadata_export" if base.blank?
      if total_files > 1
        "#{base}_part#{part_index + 1}.csv"
      else
        "#{base}.csv"
      end
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
  end
end
