# Streams asset bytes to an unauthenticated guest, for both the review and
# portal surfaces.
#
# WHY PROXY RATHER THAN HAND OUT A URL
# ------------------------------------
# The internal app resolves previews to a CDN or signed storage URL. Giving one
# of those to a guest would defeat revocation: the signed URL keeps working for
# its own lifetime no matter what happens to the link, so "withdraw this
# client's access" would not actually withdraw anything.
#
# Streaming through the app means every byte a guest receives is re-authorised
# against the live link. Revoke it and the next request fails, which is the
# behaviour a revoke button has to have to be worth having.
#
# WHY THIS IS SHARED CODE
# -----------------------
# The review and portal surfaces answer to different permission models but
# deliver bytes identically. Keeping two copies of the rights refusal and the
# storage-path resolution would mean the next fix to either lands in one of
# them, and the copy that gets missed is the one that leaks.
module GuestAssetStreaming
  extend ActiveSupport::Concern

  private

  # Refuses delivery when the asset's rights do not permit it leaving the
  # organisation.
  #
  # This guards *preview* as well as download, because for a guest there is no
  # difference: showing an internal-only asset to someone outside the company
  # is the disclosure, whether or not they were also handed a file.
  #
  # The reason is deliberately not disclosed: an unauthenticated visitor does
  # not need to be told that an asset exists but is restricted, or when its
  # licence lapsed. It is logged instead.
  #
  # @return [Boolean] true when a response has been rendered
  def refuse_on_rights!(asset)
    decision = Rights::DownloadPolicy.for(asset, audience: :external)
    return false if decision.allowed?

    Rails.logger.info(
      "[#{self.class.name}] refused asset=#{asset.id} link=#{@review_link.id} reason=#{decision.code}"
    )
    head :forbidden
    true
  end

  # Storage paths live in the +properties+ JSON, on the active version first
  # and the asset second — the same resolution order the internal asset
  # download uses.
  def preview_path_for(asset)
    version = asset.active_version
    version&.properties&.dig("preview_storage_path").presence ||
      asset.properties&.dig("preview_storage_path").presence ||
      original_path_for(asset)
  end

  def original_path_for(asset)
    asset.active_version&.properties&.dig("storage_path").presence ||
      asset.properties&.dig("storage_path").presence
  end

  # @return [Boolean] true when bytes were sent
  def stream(asset, path:, disposition:, filename: nil)
    if path.blank?
      head :not_found
      return false
    end

    # NOTE: the adapter is a required first argument. Passing only the path
    # raises ArgumentError, which the rescue below would turn into a silent
    # 404 — the exact shape of the bug this call had before the two guest
    # surfaces were merged into this concern.
    data = StorageManager.read_file_from_adapter(StorageManager.active_adapter, path)
    if data.blank?
      head :not_found
      return false
    end

    send_data data,
              type: asset.properties&.dig("content_type").presence || "application/octet-stream",
              disposition: disposition,
              filename: filename.presence || File.basename(path)
    true
  rescue ArgumentError, NoMethodError, TypeError
    # A programming error is not a missing file. Swallowing these is what let a
    # wrong-arity call to the storage adapter masquerade as "asset not found"
    # on every guest request: the surface looked merely empty rather than
    # broken, so nothing alerted and no spec failed. Let them raise.
    raise
  rescue StandardError => e
    # A missing or unreachable object is a 404 to the guest, not a stack trace.
    # The detail belongs in the log, not in an unauthenticated response.
    Rails.logger.warn("[#{self.class.name}] #{asset.id} #{path}: #{e.class}: #{e.message}")
    head :not_found
    false
  end
end
