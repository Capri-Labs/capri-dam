require "prawn"

# An annotated PDF contact sheet for offline sign-off.
#
# WHY A PDF AT ALL
# ----------------
# Approval frequently has to happen where the DAM is not: a print-out in a
# studio review, an email to a client who will never have an account, an
# archived record of what was agreed. Screenshots of a review UI lose the link
# between a mark on the image and the sentence that explains it. This keeps
# them together — every region is numbered on the artwork and the numbers key
# into the comment list underneath.
#
# WHY THE MARKS ARE DRAWN, NOT BURNED IN
# --------------------------------------
# The shapes are drawn as PDF vectors over the placed preview rather than
# composited into a raster first. That keeps them crisp at print resolution,
# avoids a round-trip through ImageMagick for every export, and means the
# normalised geometry is used exactly as stored — the same 0..1 numbers the
# browser overlay uses, mapped once onto the placed image box.
#
# NOTHING HERE MAY FAIL THE EXPORT
# --------------------------------
# A missing or unreadable preview downgrades to a text-only sheet. Feedback
# that cannot be illustrated is still feedback worth sending, and an export
# that 500s because one thumbnail never generated is worse than one without a
# picture.
module Annotations
  class ContactSheetPdf
    PAGE_MARGIN  = 36
    PLATE_HEIGHT = 320
    # Deliberately muted: the annotation's own stroke colour should be what
    # draws the eye on the plate.
    INK          = "1f2933".freeze
    MUTED        = "64748b".freeze
    RULE         = "cbd5e1".freeze

    STATUS_COLOURS = {
      "open"      => "b45309",
      "addressed" => "1d4ed8",
      "verified"  => "047857",
      "resolved"  => "475569",
    }.freeze

    # Shapes that mark a moment rather than a place, so there is nothing to
    # draw on the plate.
    NON_SPATIAL_SHAPES = %w[time].freeze

    FONT_PATH = Rails.root.join("public/fonts/Roboto-Regular.ttf")

    # @param asset [Asset]
    # @param threads [Enumerable<CommentThread>]
    def initialize(asset:, threads:)
      @asset   = asset
      @threads = threads.to_a
    end

    # @return [String] the PDF as a binary string
    def render
      pdf = Prawn::Document.new(page_size: "A4", margin: PAGE_MARGIN)
      apply_font(pdf)

      draw_header(pdf)

      if @threads.empty?
        pdf.move_down 24
        pdf.text "No review comments on this asset.", size: 11, color: MUTED
        return pdf.render
      end

      # Grouped by the version each thread was written against: markers are
      # only meaningful over the artwork they were drawn on, so mixing versions
      # onto one plate would place them over the wrong picture.
      grouped_by_version.each_with_index do |(version, threads), index|
        pdf.start_new_page if index.positive?
        draw_version_section(pdf, version, threads)
      end

      draw_footer(pdf)
      pdf.render
    end

    private

    # Prawn's built-in fonts are Windows-1252 only and raise on anything
    # outside it, which a comment body will eventually contain. Roboto is
    # already bundled for the UI, so it is reused here; an unrepresentable
    # glyph then renders as a blank box instead of aborting the export.
    def apply_font(pdf)
      return unless File.exist?(FONT_PATH)

      pdf.font_families.update(
        "Roboto" => { normal: FONT_PATH.to_s, bold: FONT_PATH.to_s, italic: FONT_PATH.to_s }
      )
      pdf.font "Roboto"
    rescue StandardError
      # Falls back to Helvetica; text is then sanitised on the way out.
      nil
    end

    def unicode_font?
      File.exist?(FONT_PATH)
    end

    # Only needed on the Helvetica fallback path.
    def safe(text)
      value = text.to_s
      return value if unicode_font?

      value.encode("Windows-1252", invalid: :replace, undef: :replace, replace: "?")
           .encode("UTF-8")
    end

    def grouped_by_version
      @threads.group_by { |thread| representative_version(thread) }
              .sort_by { |version, _| version&.version_number || 0 }
    end

    def representative_version(thread)
      thread.comments.detect { |c| c.asset_version.present? }&.asset_version ||
        thread.origin_version
    end

    # ── Chrome ────────────────────────────────────────────────────────────────

    def draw_header(pdf)
      pdf.fill_color INK
      pdf.text safe(@asset.title.to_s), size: 18, style: :bold
      pdf.move_down 4

      pdf.fill_color MUTED
      pdf.text "Review sheet · generated #{Time.current.strftime("%d %B %Y, %H:%M")}", size: 9
      pdf.text "#{@threads.size} thread#{"s" unless @threads.one?} · " \
               "#{unresolved_count} unresolved", size: 9
      pdf.move_down 10

      pdf.stroke_color RULE
      pdf.stroke_horizontal_rule
      pdf.fill_color INK
      pdf.move_down 14
    end

    def unresolved_count
      @threads.count { |t| CommentThread::OPEN_STATUSES.include?(t.status) }
    end

    def draw_footer(pdf)
      pdf.number_pages "<page> / <total>",
                       at: [ 0, -8 ],
                       width: pdf.bounds.width,
                       align: :right,
                       size: 8,
                       color: MUTED
    end

    # ── One version's plate and notes ─────────────────────────────────────────

    def draw_version_section(pdf, version, threads)
      label = version ? "Version #{version.version_number}" : "Unversioned"
      pdf.fill_color INK
      pdf.text label, size: 12, style: :bold
      pdf.move_down 8

      # Numbering is assigned before drawing so the plate and the list below
      # cannot disagree about which mark is which.
      numbered = threads.each_with_index.map { |thread, i| [ i + 1, thread ] }

      draw_plate(pdf, version, numbered)
      pdf.move_down 16
      numbered.each { |number, thread| draw_thread(pdf, number, thread) }
    end

    def draw_plate(pdf, version, numbered)
      image = preview_io(version)
      return if image.blank?

      top = pdf.cursor
      placed = pdf.image(image, position: :center, fit: [ pdf.bounds.width, PLATE_HEIGHT ])

      box = {
        left:   placed.instance_variable_get(:@x) || 0,
        bottom: pdf.cursor,
        width:  placed.scaled_width,
        height: placed.scaled_height,
      }
      # Prawn does not expose the placed x for a centred image, so it is
      # recomputed from the known centring rather than trusted.
      box[:left]   = (pdf.bounds.width - box[:width]) / 2.0
      box[:bottom] = top - box[:height]

      numbered.each { |number, thread| draw_markers(pdf, box, number, thread) }
    rescue StandardError => e
      # A corrupt or unsupported preview must not take the whole sheet down.
      Rails.logger.warn("[ContactSheetPdf] plate skipped for asset #{@asset.id}: #{e.message}")
      nil
    end

    def preview_io(version)
      path = version&.properties&.dig("preview_storage_path") ||
             @asset.properties&.dig("preview_storage_path")
      return nil if path.blank?

      bytes = StorageManager.read_file_from_adapter(StorageManager.active_adapter, path)
      return nil if bytes.blank?

      StringIO.new(bytes)
    rescue StandardError => e
      Rails.logger.warn("[ContactSheetPdf] preview unavailable for asset #{@asset.id}: #{e.message}")
      nil
    end

    # ── Marks ─────────────────────────────────────────────────────────────────

    def draw_markers(pdf, box, number, thread)
      targets = thread.comments.flat_map(&:annotation_targets)
                      .reject { |t| NON_SPATIAL_SHAPES.include?(t.shape) }
      return if targets.empty?

      targets.each { |target| draw_shape(pdf, box, target) }
      draw_badge(pdf, box, number, targets.first)
    end

    # Normalised (0..1, top-left origin) into PDF user space (bottom-left
    # origin) — the y flip is the whole of the conversion.
    def point(box, x, y)
      [ box[:left] + (x.to_f * box[:width]), box[:bottom] + ((1.0 - y.to_f) * box[:height]) ]
    end

    def draw_shape(pdf, box, target)
      style = target.style.presence || AnnotationTarget::DEFAULT_STYLE
      pdf.stroke_color(style["stroke_color"].to_s.delete("#").presence || "ef4444")
      # stroke_width is stored as a fraction of the shorter source dimension,
      # so it has to be scaled to the placed box rather than used as points.
      pdf.line_width([ style["stroke_width"].to_f * [ box[:width], box[:height] ].min, 0.5 ].max)

      case target.shape
      when "rect", "highlight", "text" then stroke_box(pdf, box, target)
      when "ellipse"                   then stroke_ellipse(pdf, box, target)
      when "pin"                       then stroke_pin(pdf, box, target)
      when "line", "freehand"          then stroke_path(pdf, box, target)
      when "arrow"                     then stroke_path(pdf, box, target, arrowhead: true)
      else stroke_box(pdf, box, target)
      end
    ensure
      pdf.stroke_color INK
      pdf.line_width 1
    end

    def stroke_box(pdf, box, target)
      origin = point(box, target.bbox_x, target.bbox_y)
      pdf.stroke_rectangle(origin, target.bbox_w * box[:width], target.bbox_h * box[:height])
    end

    def stroke_ellipse(pdf, box, target)
      centre = point(box, target.bbox_x + (target.bbox_w / 2), target.bbox_y + (target.bbox_h / 2))
      rx = [ (target.bbox_w * box[:width]) / 2, 0.5 ].max
      ry = [ (target.bbox_h * box[:height]) / 2, 0.5 ].max
      pdf.stroke_ellipse(centre, rx, ry)
    end

    def stroke_pin(pdf, box, target)
      pdf.stroke_circle(point(box, target.bbox_x, target.bbox_y), 5)
    end

    # Stored paths are plain "M x,y L x,y …" polylines in a viewBox="0 0 1 1"
    # space (see annotationGeometry.js#pathFromPoints), so no curve handling is
    # needed — anything else is ignored rather than guessed at.
    def stroke_path(pdf, box, target, arrowhead: false)
      points = parse_path(target.svg_path).map { |(x, y)| point(box, x, y) }
      return stroke_box(pdf, box, target) if points.size < 2

      points.each_cons(2) { |from, to| pdf.stroke_line(from, to) }
      draw_arrowhead(pdf, points[-2], points[-1]) if arrowhead
    end

    def parse_path(path)
      return [] if path.blank?

      path.to_s.scan(/[ML]\s*(-?[\d.]+)[,\s]+(-?[\d.]+)/i).map { |x, y| [ x.to_f, y.to_f ] }
    end

    # Direction is carried by the path, not the bbox — an arrow drawn
    # right-to-left has the same bounding box as one drawn left-to-right, so
    # the head has to come from the final segment.
    def draw_arrowhead(pdf, from, to)
      angle  = Math.atan2(to[1] - from[1], to[0] - from[0])
      length = 9
      spread = 0.4

      [ angle + Math::PI - spread, angle + Math::PI + spread ].each do |theta|
        pdf.stroke_line(to, [ to[0] + (Math.cos(theta) * length), to[1] + (Math.sin(theta) * length) ])
      end
    end

    # A filled disc keyed to the list below. Placed at the mark's top-left and
    # nudged inside the plate so a mark against an edge is not clipped.
    def draw_badge(pdf, box, number, target)
      centre = point(box, target.bbox_x, target.bbox_y)
      radius = 8
      x = centre[0].clamp(box[:left] + radius, box[:left] + box[:width] - radius)
      y = centre[1].clamp(box[:bottom] + radius, box[:bottom] + box[:height] - radius)

      pdf.fill_color INK
      pdf.fill_circle([ x, y ], radius)
      pdf.fill_color "ffffff"
      pdf.draw_text number.to_s, at: [ x - (number.to_s.length * 2.6), y - 3 ], size: 8
      pdf.fill_color INK
    end

    # ── Notes ─────────────────────────────────────────────────────────────────

    def draw_thread(pdf, number, thread)
      pdf.start_new_page if pdf.cursor < 90

      pdf.fill_color INK
      pdf.text "#{number}. #{safe(thread_heading(thread))}", size: 10, style: :bold
      pdf.fill_color STATUS_COLOURS.fetch(thread.status, MUTED)
      pdf.text thread.status.humanize, size: 8
      pdf.fill_color INK
      pdf.move_down 3

      thread.comments.select { |c| c.deleted_at.nil? }
            .sort_by(&:created_at)
            .each { |comment| draw_comment(pdf, comment) }

      pdf.move_down 6
      pdf.stroke_color RULE
      pdf.stroke_horizontal_rule
      pdf.fill_color INK
      pdf.move_down 10
    end

    # The heading names *where* the note points, which is what a reader with a
    # print-out needs in order to find it.
    def thread_heading(thread)
      target = thread.comments.flat_map(&:annotation_targets).first
      return "General note" if target.blank?

      if target.start_frame.present?
        span = target.range? ? "#{target.start_timecode} – #{target.end_timecode}" : target.start_timecode
        return "#{target.shape.humanize} at #{span}"
      end

      return "Page #{target.page}" if target.page.present?

      target.label.presence || "#{target.shape.humanize} annotation"
    end

    def draw_comment(pdf, comment)
      pdf.fill_color MUTED
      pdf.text "#{safe(comment.author_display_name)} · #{comment.created_at.strftime("%d %b %Y %H:%M")}" \
               "#{comment.reply? ? " · reply" : ""}",
               size: 7.5, indent_paragraphs: comment.reply? ? 16 : 0
      pdf.fill_color INK
      pdf.text safe(comment.body), size: 9.5, indent_paragraphs: comment.reply? ? 16 : 0
      pdf.move_down 4
    end
  end
end
