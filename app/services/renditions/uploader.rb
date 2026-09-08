# Stores an uploaded file as a {Rendition} of an asset.
#
# The awkward part of a manual rendition is that +renditions.storage_backend_id+
# is NOT NULL, so "where does this go?" has to be answered before the row can
# exist. The pipeline never had to ask — it writes wherever the process happens
# to be pointing. Here the backend is resolved explicitly and recorded, and the
# bytes are written through *that same record's* adapter, so what the row claims
# and where the object actually is cannot drift apart.
#
# If no backend is active the upload is refused rather than guessed at. Storing
# somewhere we cannot name would produce a row we could never resolve again.
module Renditions
  class Uploader
    # Raised when the upload cannot be placed. Callers translate this into a
    # 4xx rather than a 500: it is a configuration problem, not a bug.
    class UnavailableBackendError < StandardError; end

    Result = Struct.new(:rendition, keyword_init: true)

    def initialize(asset:, file:, kind:, metadata: {})
      @asset    = asset
      @file     = file
      @kind     = kind.to_s.strip.downcase
      @metadata = metadata || {}
    end

    def call
      backend = active_backend
      key     = storage_key_for(backend)

      # Written before the row exists, so a validation failure below leaves an
      # orphaned object rather than a row pointing at nothing. Of the two, the
      # orphan is the one that cannot corrupt a later read — and it is cleaned
      # up immediately below.
      backend.adapter.store(rewound_file, key, content_type: content_type)

      rendition = Rendition.new(
        asset: @asset,
        storage_backend: backend,
        kind: @kind,
        storage_key: key,
        content_type: content_type,
        file_size: file_size,
        **dimensions,
        metadata: @metadata.merge("source" => "manual"),
      )

      discard_object(backend, key) unless rendition.save

      Result.new(rendition: rendition)
    end

    private

    def active_backend
      backend = StorageBackend.find_by(active: true)
      return backend if backend

      raise UnavailableBackendError,
            "No active storage backend is configured, so there is nowhere to put this rendition."
    end

    # Namespaced by asset uuid and suffixed with entropy so re-uploading the
    # same kind never overwrites the object a still-live row points at.
    def storage_key_for(_backend)
      "renditions/#{@asset.uuid}/#{@kind}_#{SecureRandom.hex(6)}#{extension}"
    end

    def extension
      ext = File.extname(@file.try(:original_filename).to_s)
      ext.match?(/\A\.[A-Za-z0-9]{1,10}\z/) ? ext.downcase : ""
    end

    def content_type
      @file.try(:content_type).presence || "application/octet-stream"
    end

    def file_size
      size = @file.try(:size).to_i
      size.positive? ? size : nil
    end

    # Derived here rather than accepted from the client: the dimensions are a
    # property of the file, and a caller that reports them wrongly would make
    # every downstream layout decision wrong with it.
    #
    # Non-images (and files ImageMagick cannot read) simply have no dimensions;
    # that is a normal outcome for a PDF or an audio proxy, not an error.
    def dimensions
      return {} unless content_type.start_with?("image/")
      return {} if @file.try(:path).blank?

      image = MiniMagick::Image.open(@file.path)
      { width: image.width, height: image.height }
    rescue StandardError => e
      Rails.logger.info("Renditions::Uploader: no dimensions for #{content_type}: #{e.message}")
      {}
    end

    def discard_object(backend, key)
      backend.adapter.delete(key)
    rescue StandardError => e
      Rails.logger.warn("Renditions::Uploader: could not roll back #{key}: #{e.message}")
    end

    def rewound_file
      @file.rewind if @file.respond_to?(:rewind)
      @file
    end
  end
end
