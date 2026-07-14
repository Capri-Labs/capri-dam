require "zip"

# Sidekiq worker that builds the ZIP archive backing the Explorer's bulk
# "Download" overlay (Api::V1::AssetDownloadsController).
#
# == Processing pipeline
#
# 1. Recursively walks the download's +folder_ids+ (expanding every active
#    subfolder) and its flat +asset_ids+, building a flat list of
#    (asset, zip_path) pairs. Folder-sourced assets are nested under their
#    folder's name (and its subfolder path) inside the archive; directly
#    selected assets land at the archive root. Name collisions are resolved
#    by appending " (2)", " (3)", etc.
# 2. Streams each asset's active-version file into the ZIP one at a time
#    (never loading the whole archive into memory at once), reading bytes
#    via +storage_path+ — the authoritative file location written by the
#    upload/processing pipeline (see AssetProcessorWorker) — through
#    whichever storage provider is active. Progress (+processed_items+) is
#    persisted periodically so the Explorer's polling progress bar advances
#    smoothly without hammering the database on every single file.
# 3. Attaches the finished ZIP to the {AssetDownload} (a plain bigint-keyed
#    model, so ActiveStorage attachment lookups are reliable — unlike the
#    UUID-keyed Asset/AssetVersion/Folder models) and notifies the user via
#    both {Notification} and their {InboxMessage} inbox with a direct
#    download link, so they can retrieve it later even if they've navigated
#    away or closed the tab that requested it.
#
# == Queue & throttle policy
#
# * Queue:   +downloads+ (low priority — heavy I/O, never blocks user-facing work)
# * Retries: 3
# * Concurrency ceiling: 3 simultaneous jobs (via Sidekiq::Throttled) — a
#   soft global cap so a burst of large downloads can't starve the box.
#   {Api::V1::AssetDownloadsController#create} additionally tells the
#   client immediately (`queued: true`) when the requesting user already has
#   another pending/processing download, since Sidekiq processes same-queue
#   jobs roughly in order.
#
# @see AssetDownload
# @see AssetDownloadCleanupWorker
class AssetDownloadWorker
  include Sidekiq::Worker
  include Sidekiq::Throttled::Worker

  sidekiq_options queue: "downloads", retry: 3

  sidekiq_throttle(concurrency: { limit: 3 })

  # How many files to zip between progress persists — keeps the progress
  # bar responsive without issuing an UPDATE per file for huge selections.
  PROGRESS_BATCH_SIZE = 5

  def perform(download_id)
    download = AssetDownload.find_by(id: download_id)
    return unless download
    return if download.completed? # idempotent guard against re-runs

    download.update!(status: :processing, processed_items: 0)

    entries = collect_entries(download)
    tmp_path = Rails.root.join("tmp", "asset_download_#{download.id}_#{SecureRandom.hex(8)}.zip")

    processed = 0
    Zip::File.open(tmp_path.to_s, create: true) do |zipfile|
      entries.each do |asset, zip_path|
        write_entry(zipfile, asset, zip_path)
        processed += 1
        download.update!(processed_items: processed) if (processed % PROGRESS_BATCH_SIZE).zero?
      end
    end

    byte_size = File.size(tmp_path)
    File.open(tmp_path, "rb") do |file|
      download.zip_file.attach(
        io: file,
        filename: "#{download.name}.zip",
        content_type: "application/zip"
      )
    end

    download.update!(
      status:          :completed,
      processed_items: entries.size,
      file_count:      1,
      byte_size:       byte_size,
      expires_at:      Time.current + AssetDownload::RETENTION_PERIOD,
      error_message:   nil
    )

    notify_user(download, success: true)
  rescue StandardError => e
    Rails.logger.error "💥 AssetDownloadWorker failed for ##{download_id}: #{e.message}"
    download&.update(status: :failed, error_message: e.message)
    notify_user(download, success: false) if download
    raise e
  ensure
    FileUtils.rm_f(tmp_path) if tmp_path.present?
  end

  private

  # Builds the flat list of (Asset, zip-internal path) pairs to write,
  # expanding every folder in +download.folder_ids+ recursively and
  # resolving name collisions across the whole archive.
  def collect_entries(download)
    entries    = []
    used_paths = Set.new

    Asset.active.where(id: download.asset_ids).find_each do |asset|
      add_entry(entries, used_paths, asset, sanitize_segment(filename_for(asset)))
    end

    Folder.active.where(id: download.folder_ids).find_each do |folder|
      collect_folder_entries(folder, sanitize_segment(folder.name), entries, used_paths)
    end

    entries
  end

  def collect_folder_entries(folder, path_prefix, entries, used_paths)
    folder.assets.active.find_each do |asset|
      add_entry(entries, used_paths, asset, "#{path_prefix}/#{sanitize_segment(filename_for(asset))}")
    end

    folder.children.active.find_each do |child|
      collect_folder_entries(child, "#{path_prefix}/#{sanitize_segment(child.name)}", entries, used_paths)
    end
  end

  def add_entry(entries, used_paths, asset, path)
    path = unique_path(used_paths, path)
    used_paths << path
    entries << [ asset, path ]
  end

  def unique_path(used_paths, path)
    return path unless used_paths.include?(path)

    ext  = File.extname(path)
    base = path.delete_suffix(ext)
    n = 2
    candidate = "#{base} (#{n})#{ext}"
    while used_paths.include?(candidate)
      n += 1
      candidate = "#{base} (#{n})#{ext}"
    end
    candidate
  end

  def filename_for(asset)
    version  = asset.active_version
    original = asset.properties&.dig("original_filename") || version&.properties&.dig("original_filename")
    original.presence || asset.title.presence || "asset-#{asset.uuid}"
  end

  # Strips directory traversal sequences and characters unsafe inside a ZIP
  # entry path, mirroring the sanitisation already applied to uploaded
  # filenames elsewhere (see Api::V1::AssetsController#create).
  def sanitize_segment(name)
    File.basename(name.to_s).gsub(%r{[/\\]}, "_").gsub(/[^\w.\- ()]/, "_").presence || "untitled"
  end

  def write_entry(zipfile, asset, zip_path)
    version      = asset.active_version
    storage_path = version&.properties&.fetch("storage_path", nil) || asset.properties&.fetch("storage_path", nil)

    unless storage_path.present?
      Rails.logger.warn "[AssetDownloadWorker] Skipping asset ##{asset.id} — no storage_path on active version."
      return
    end

    bytes = read_file_bytes(storage_path)
    return if bytes.nil?

    zipfile.get_output_stream(zip_path) { |out| out.write(bytes) }
  end

  # Reads the raw bytes for +storage_path+ from disk.
  #
  # Deliberately mirrors Api::V1::AssetsController#serve_local's
  # battle-tested resolution instead of +StorageManager.active_adapter+:
  # the latter is built from the +Setting+ ("active_storage_provider") the
  # Settings UI writes, which is a *separate*, independently-editable value
  # from the {StorageBackend} row actually flagged +active: true+ that
  # +AssetProcessorWorker+ used to physically write the file at upload time.
  # These two can drift out of sync (e.g. an admin previewing/selecting a
  # different provider in Settings without actually cutting the active
  # backend over), which silently broke bulk downloads: assets were skipped
  # (no bytes read, no error surfaced) whenever the Settings value pointed
  # at a provider the file was never actually written to.
  #
  # So: always try the local "storage/dam" root directly first — the same
  # physical root {StorageAdapters::LocalStorageAdapter} and +serve_local+
  # both use — and only fall back to the adapter for whichever
  # {StorageBackend} is genuinely active for files that really do live
  # remotely.
  def read_file_bytes(storage_path)
    local_root = StorageAdapters::LocalStorageAdapter::ROOT.call
    local_candidate = local_root.join(storage_path.to_s.sub(%r{\A/}, ""))
    if File.expand_path(local_candidate).start_with?(local_root.to_s) && File.exist?(local_candidate)
      return File.binread(local_candidate)
    end

    backend = StorageBackend.find_by(active: true)
    storage = backend ? StorageManager.adapter_for(backend) : StorageManager.active_adapter
    return nil unless storage.respond_to?(:download)

    storage.download(storage_path)
  rescue StandardError => e
    Rails.logger.error "[AssetDownloadWorker] Could not read #{storage_path}: #{e.message}"
    nil
  end

  def notify_user(download, success:)
    return unless download.user

    download_url = Rails.application.routes.url_helpers.download_api_v1_asset_download_path(download)

    if success
      Notification.create!(
        user:       download.user,
        title:      "Download ready",
        message:    "“#{download.name}” finished — #{download.total_items} file(s) zipped.",
        action_url: download_url
      )
      InboxDeliveryService.deliver(
        recipient:    download.user,
        subject:      "Your download “#{download.name}” is ready",
        body_html:    "<p>Your requested download <strong>#{ERB::Util.html_escape(download.name)}</strong> " \
                       "(#{download.total_items} file(s)) has finished zipping.</p>" \
                       "<p><a href=\"#{ERB::Util.html_escape(download_url)}\">Click here to download the ZIP</a></p>",
        message_type: "notification",
        metadata:     { "asset_download_id" => download.id }
      )
    else
      Notification.create!(
        user:       download.user,
        title:      "Download failed",
        message:    "“#{download.name}” could not be generated. #{download.error_message}".strip,
        action_url: nil
      )
      InboxDeliveryService.deliver(
        recipient:    download.user,
        subject:      "Your download “#{download.name}” failed",
        body_html:    "<p>Your requested download <strong>#{ERB::Util.html_escape(download.name)}</strong> " \
                       "could not be completed: #{ERB::Util.html_escape(download.error_message.to_s)}</p>",
        message_type: "notification",
        metadata:     { "asset_download_id" => download.id }
      )
    end
  rescue StandardError => e
    Rails.logger.error "⚠️ Failed to notify user for download ##{download.id}: #{e.message}"
  end
end
