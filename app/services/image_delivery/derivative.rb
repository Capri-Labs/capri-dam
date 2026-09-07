module ImageDelivery
  # Produces — and caches — a re-encoded copy of a stored image for delivery.
  #
  # WHY A CONTENT-ADDRESSED DISK CACHE AND NOT A +renditions+ ROW
  # ------------------------------------------------------------
  # A delivery derivative is disposable: it can be regenerated from the
  # original at any time, it has no independent identity, and nobody should
  # ever have to manage its lifecycle. Giving it a database row would mean
  # inventing a storage backend for it, keeping the row in step with the file,
  # and cleaning both up on re-upload. Keying the file by a digest of the
  # source's identity plus the encode settings gets invalidation for free —
  # re-uploading changes the source's size/mtime, which changes the key, so the
  # stale derivative is simply never asked for again.
  #
  # WHY IT CAN DECIDE NOT TO
  # ------------------------
  # AVIF is usually much smaller, but not always: on small images the format's
  # fixed overhead can exceed what it saves, and re-encoding an already-lean
  # JPEG can produce something *bigger*. Serving that would make the page
  # slower while reporting success, so a derivative that is not smaller than
  # its source is thrown away and the original served instead. The point of the
  # feature is fewer bytes, not newer formats.
  #
  # Every failure path returns nil rather than raising. This runs inline on an
  # image request: a transcode that fails must degrade to the original, never
  # turn a working image into a 500.
  class Derivative
    CACHE_ROOT = "storage/dam/.derivatives".freeze

    # Above this the transcode cost is not worth paying on a request thread;
    # such originals are served as-is.
    MAX_SOURCE_BYTES = 25.megabytes

    # AVIF at q50 is visually comparable to JPEG at a much higher number; WebP
    # tracks JPEG's scale more closely.
    QUALITY = { "avif" => 50, "webp" => 80 }.freeze

    Result = Struct.new(:path, :content_type, :format, keyword_init: true)

    class << self
      # @param source_path [String] absolute path to the stored original
      # @param format [String] "avif" or "webp"
      # @param content_type [String] MIME type to serve the derivative as
      # @return [Result, nil] nil means "serve the original"
      def fetch(source_path:, format:, content_type:)
        return nil unless File.file?(source_path)

        stat = File.stat(source_path)
        return nil if stat.size > MAX_SOURCE_BYTES
        return nil if stat.size.zero?

        cached = cache_path(source_path, stat, format)
        unless File.exist?(cached)
          return nil unless generate(source_path, cached, format, stat.size)
        end

        Result.new(path: cached.to_s, content_type: content_type, format: format)
      rescue StandardError => e
        Rails.logger.warn("[ImageDelivery] derivative failed for #{source_path}: #{e.message}")
        nil
      end

      private

      # Keyed on what the source *is* (path, size, mtime) plus how it would be
      # encoded, so a re-upload or a quality change misses the cache instead of
      # serving something stale.
      def cache_path(source_path, stat, format)
        digest = Digest::SHA256.hexdigest(
          [ source_path, stat.size, stat.mtime.to_i, format, QUALITY[format] ].join("|"),
        )

        Rails.root.join(CACHE_ROOT, digest[0, 2], "#{digest}.#{format}")
      end

      # @return [Boolean] whether a usable derivative now exists at +target+
      def generate(source_path, target, format, source_bytes)
        FileUtils.mkdir_p(target.dirname)

        # Written to a unique temp file and moved into place, so two concurrent
        # requests for the same image cannot serve each other a half-written
        # file. rename(2) within one filesystem is atomic.
        tmp = target.sub_ext(".#{SecureRandom.hex(8)}.tmp")

        image = MiniMagick::Image.open(source_path)
        image.format(format)
        image.quality(QUALITY.fetch(format).to_s)
        image.strip
        image.write(tmp.to_s)

        unless File.exist?(tmp) && File.size(tmp).positive?
          FileUtils.rm_f(tmp)
          return false
        end

        # The whole point is fewer bytes. If this encode is not smaller, keep
        # the original and remember nothing.
        if File.size(tmp) >= source_bytes
          FileUtils.rm_f(tmp)
          return false
        end

        FileUtils.mv(tmp.to_s, target.to_s)
        true
      rescue StandardError => e
        FileUtils.rm_f(tmp) if tmp
        Rails.logger.warn("[ImageDelivery] transcode to #{format} failed: #{e.message}")
        false
      end
    end
  end
end
