require "net/http"
require "uri"

module IngestionAdapters
  # Adobe Experience Manager Assets Adapter
  #
  # Uses AEM's QueryBuilder servlet (`/bin/querybuilder.json`), NOT the legacy
  # "Assets HTTP API" (`/api/assets/**.json`) — that bundle is not installed on
  # modern AEM as a Cloud Service instances and 404s there. QueryBuilder ships
  # with every AEM instance (on-prem and Cloud Service) and supports proper
  # offset/limit pagination plus "selective" hits, which lets us pull the
  # dam:Asset node's `jcr:content/metadata/*` properties in the *same* request
  # (no N+1 per-asset metadata fetch).
  #
  # Docs: https://experienceleague.adobe.com/en/docs/experience-manager-65/content/implementing/developing/full-stack/querybuilder-api
  #
  # Credentials: endpoint (AEM Author URL), auth_token (IMS Bearer access
  # token), root_path (optional — DAM folder to scope the migration to, e.g.
  # "/content/dam/US/marketing-assets/product-assets". Defaults to the whole
  # /content/dam tree.)
  class AemAdapter < Base
    PAGE_SIZE = 100
    DEFAULT_ROOT = "/content/dam"

    # jcr:content-relative properties pulled via QueryBuilder's "selective"
    # hits mode — avoids a second HTTP round-trip per asset for metadata.
    SELECTIVE_PROPERTIES = %w[
      jcr:path
      jcr:content/metadata/dc:title
      jcr:content/metadata/dc:description
      jcr:content/metadata/dc:format
      jcr:content/metadata/dam:size
      jcr:content/metadata/cq:tags
      jcr:content/metadata/dc:creator
      jcr:content/jcr:createdBy
      jcr:content/jcr:created
    ].join(" ").freeze

    # When the AEM Assets HTTP/JCR APIs return a node's properties, the
    # `jcr:` prefix on a handful of well-known properties is transparently
    # rewritten to the Dublin Core (`dc:`) prefix — e.g. `jcr:title` comes
    # back as `dc:title`. We still check the raw `jcr:` keys defensively in
    # case an older/on-prem AEM instance doesn't apply the substitution.
    #
    # See: https://experienceleague.adobe.com/docs/experience-manager-65/content/implementing/developing/full-stack/assets-http-api
    JCR_TO_DC_PROPERTY_ALIASES = {
      "jcr:title"       => "dc:title",
      "jcr:description" => "dc:description",
      "jcr:language"    => "dc:language",
    }.freeze

    # AEM sometimes reports non-standard/legacy MIME type spellings in
    # `dc:format` (AEM's "MIME types" per its Schema Editor docs) instead of
    # the canonical value the rest of the platform expects (AEM's "Schema
    # Form" value). This table normalizes AEM's variant spelling (map key,
    # lowercased) to the canonical form (map value) so downstream content
    # negotiation, previews, and search facets behave consistently.
    #
    # AEM MIME type variant (lowercased)                 => Canonical "Schema Form" value
    MIME_TYPE_NORMALIZATION_MAP = {
      "image/pjpeg"                                       => "image/jpeg",
      "image/x-tiff"                                       => "image/tiff",
      "application/postscript"                             => "application/pdf",
      "multipart/related; type=application/x-imageset"     => "application/x-ImageSet",
      "multipart/related; type=application/x-spinset"      => "application/x-SpinSet",
      "multipart/related; type=application/x-mixedmediaset" => "application/x-MixedMediaSet",
      "video/x-quicktime"                                  => "video/quicktime",
      "video/mp4"                                          => "video/mpeg4",
      "video/x-ms-wmv"                                     => "video/wmv",
      "video/x-flv"                                         => "video/flv",
      "video/avi"                                           => "video/avi",
      "video/msvideo"                                       => "video/avi",
      "video/x-msvideo"                                     => "video/avi",
    }.freeze

    def fetch_next_chunk(cursor = nil, limit = PAGE_SIZE)
      start_offset = cursor.to_i
      data  = get_json(query_builder_url(start: start_offset, limit: limit))
      hits  = Array(data["hits"])
      total = data["total"].to_i

      files = hits.map { |hit| build_file_entry(hit) }

      {
        files:       files,
        next_cursor: (start_offset + hits.size).to_s,
        has_more:    (start_offset + hits.size) < total,
      }
    end

    def download_and_stream(file_identifier, &block)
      # AEM download URL: /path/to/asset/jcr:content/renditions/original
      download_url = file_identifier.end_with?("/jcr:content/renditions/original") ?
                     file_identifier :
                     "#{file_identifier}/jcr:content/renditions/original"

      ext = File.extname(file_identifier).presence || ".bin"
      stream_http_file("#{endpoint}#{download_url}", ext, &block)
    end

    def test_connection
      # Try to fetch a single asset from the root DAM folder (or the requested
      # scoped folder) to confirm the path is valid and QueryBuilder is reachable.
      get_json(query_builder_url(start: 0, limit: 1))
      { success: true, message: "Connected to AEM at #{endpoint}. Folder #{scoped_path} is accessible." }
    rescue => e
      { success: false, message: "AEM connection failed: #{e.message}" }
    end

    private

    def query_builder_url(start:, limit:)
      params = {
        "path"         => scoped_path,
        "type"         => "dam:Asset",
        "p.limit"      => limit,
        "p.offset"     => start,
        "p.hits"       => "selective",
        "p.properties" => SELECTIVE_PROPERTIES,
      }
      "#{endpoint}/bin/querybuilder.json?#{URI.encode_www_form(params)}"
    end

    def build_file_entry(hit)
      path     = hit["jcr:path"]
      content  = hit["jcr:content"] || {}
      metadata = content["metadata"] || {}

      selective_metadata = {
        "title"        => metadata["dc:title"],
        "description"  => metadata["dc:description"],
        "tags"         => Array(metadata["cq:tags"]),
        "creator"      => metadata["dc:creator"] || content["jcr:createdBy"],
        "created"      => content["jcr:created"],
        "content_type" => metadata["dc:format"],
      }.compact

      raw_full_metadata = migrate_metadata? ? fetch_raw_full_metadata(path) : {}
      full_metadata      = normalize_full_metadata(raw_full_metadata)

      # Full per-asset metadata (when enabled) takes priority over the
      # lightweight selective properties, since it reflects every property
      # under jcr:content/metadata rather than just the hand-picked subset.
      merged_metadata = selective_metadata.merge(full_metadata)
      merged_metadata["content_type"] = normalize_mime_type(merged_metadata["content_type"])
      merged_metadata.compact!

      {
        identifier:    path,
        size:          metadata["dam:size"].to_i,
        original_name: File.basename(path.to_s),
        metadata:      merged_metadata,
        # The untouched payload from the jcr:content/metadata.json call (when
        # migrate_metadata is enabled) — kept separate from the canonical
        # `metadata:` mapping above so the Batch Review audit view can show
        # operators exactly what was fetched from the source system.
        raw_metadata:  raw_full_metadata,
      }
    end

    # Whether this batch is configured to fetch complete per-asset metadata.
    # Defaults to +true+ when no batch is present (e.g. #test_connection) or
    # the batch/column predates this feature, matching the enabled-by-default
    # product requirement.
    def migrate_metadata?
      return true unless batch.respond_to?(:migrate_metadata?)
      batch.migrate_metadata?
    end

    # Fetches the *complete* metadata node for a single asset — i.e. every
    # property under `jcr:content/metadata`, not just the hand-picked
    # SELECTIVE_PROPERTIES subset pulled alongside the file listing. This
    # costs one extra HTTP round-trip per asset, so it's opt-out (via the
    # migration wizard's "Migrate Metadata" toggle) rather than always-on.
    #
    # Returns the raw, untouched JSON payload (or {} on failure) — callers
    # that need the canonical schema mapping should pass this through
    # #normalize_full_metadata. Keeping the raw payload available separately
    # lets the ingestion pipeline persist it verbatim for audit purposes
    # (see IngestionItem#full_metadata).
    #
    # @param path [String] absolute JCR path of the dam:Asset node
    # @return [Hash] raw jcr:content/metadata.json payload, or +{}+ if the
    #   fetch fails — a failure here must never abort the whole batch chunk.
    def fetch_raw_full_metadata(path)
      get_json("#{endpoint}#{path}/jcr:content/metadata.json")
    rescue => e
      Rails.logger.warn("[AemAdapter] Full metadata fetch failed for #{path}: #{e.message}")
      {}
    end

    # Applies the jcr:→dc: aliasing, then maps AEM's dc:/cq: keys to our
    # canonical metadata schema (same target keys as the selective mapping).
    def normalize_full_metadata(data)
      return {} unless data.is_a?(Hash)

      resolved = data.dup
      JCR_TO_DC_PROPERTY_ALIASES.each do |jcr_key, dc_key|
        resolved[dc_key] ||= data[jcr_key]
      end

      {
        "title"        => resolved["dc:title"],
        "description"  => resolved["dc:description"],
        "tags"         => Array(resolved["cq:tags"]).presence,
        "creator"      => resolved["dc:creator"],
        "created"      => resolved["jcr:created"],
        "content_type" => resolved["dc:format"],
        "language"     => resolved["dc:language"],
      }.compact
    end

    # Looks up AEM's variant MIME type spelling in MIME_TYPE_NORMALIZATION_MAP
    # and returns the canonical form; passes through unrecognized/blank values
    # unchanged.
    def normalize_mime_type(content_type)
      return content_type if content_type.blank?
      MIME_TYPE_NORMALIZATION_MAP[content_type.to_s.downcase] || content_type
    end

    # Normalizes the configured root_path into the path segment QueryBuilder
    # expects, always relative to /content/dam (AEM's DAM root).
    def scoped_path
      raw = credentials["root_path"].to_s.strip
      return "/content/dam" if raw.blank?

      path = raw.start_with?("/content/dam") ? raw : File.join(DEFAULT_ROOT, raw.delete_prefix("/"))
      path.chomp("/")
    end
  end
end
