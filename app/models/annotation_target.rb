# Where on the media a {Comment} points.
#
# A comment may have zero targets (a plain thread-level remark) or several —
# one comment can, for example, circle two different regions of the same image,
# or span multiple pages of a PDF.
#
# COORDINATES ARE ALWAYS NORMALISED
# ---------------------------------
# +bbox_x+, +bbox_y+, +bbox_w+ and +bbox_h+ are fractions of the source
# dimensions in the range 0..1, with an upper-left origin — never pixels. A
# normalised region survives responsive layout, thumbnails, renditions, CDN
# transforms, and retina scaling; a pixel region does not. A database CHECK
# constraint enforces the range.
#
# Two representations are stored together on purpose:
#
#   * the bbox is always populated (for a +pin+, +bbox_w+/+bbox_h+ are 0) and is
#     indexed — it drives hit-testing and the "did this region change between
#     versions?" lookup;
#   * +svg_path+ is the fidelity layer, a geometry-only path in a
#     <tt>viewBox="0 0 1 1"</tt> space, which expresses ellipse, arrow, line and
#     freehand alike and can be rendered by the browser with no conversion.
#
# This mirrors the W3C Web Annotation Data Model's FragmentSelector /
# SvgSelector split (https://www.w3.org/TR/annotation-model/), including its
# recommendation to keep styling *out* of the SVG — hence the separate
# {#style} JSONB column, whose +stroke_width+ is a fraction of the shorter
# source dimension rather than a pixel count, so strokes scale with the media.
#
# VIDEO TIME IS FRAME-NATIVE
# --------------------------
# Positions are stored as frame integers plus +fps+, not milliseconds. Seconds
# and SMPTE timecode are both derivable from a frame number, but a frame number
# cannot be recovered from a rounded millisecond value — so storing
# milliseconds throws away frame accuracy permanently. Setting +end_frame+
# turns a point-in-time comment into a range ("in/out point") comment.
class AnnotationTarget < ApplicationRecord
  MEDIA_TYPES = %w[image video document].freeze

  # +pin+      — a point marker
  # +rect+     — rectangle (bbox alone is sufficient)
  # +ellipse+  — ellipse inscribed in the bbox
  # +arrow+    — arrow from one point to another
  # +line+     — straight line
  # +freehand+ — pencil stroke, requires an svg_path
  # +text+     — a text callout anchored at the bbox
  # +highlight+— a document text highlight
  # +time+     — a position (or range) on a video timeline with no spatial
  #              extent: "at 0:14 the music is too loud". Its bbox is all
  #              zeroes and it is deliberately *not* drawn on the video
  #              overlay — it belongs on the scrubber's marker track only.
  #              Without it, commenting on a moment would force the reviewer to
  #              draw a meaningless shape somewhere on the frame.
  SHAPES = %w[pin rect ellipse arrow line freehand text highlight time].freeze

  # Shapes whose geometry cannot be reconstructed from a bounding box alone.
  PATH_REQUIRED_SHAPES = %w[arrow line freehand].freeze

  DEFAULT_STYLE = {
    "stroke_color" => "#ef4444",
    # Fraction of the shorter source dimension, NOT pixels.
    "stroke_width" => 0.004,
    "fill" => "none",
    "opacity" => 1.0,
  }.freeze

  belongs_to :comment

  validates :media_type, inclusion: { in: MEDIA_TYPES }
  validates :shape, inclusion: { in: SHAPES }
  validates :bbox_x, :bbox_y, :bbox_w, :bbox_h,
            presence: true,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }
  validates :start_frame, :end_frame,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 },
            allow_nil: true
  validates :fps, numericality: { greater_than: 0 }, allow_nil: true
  validates :page, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  validate :bbox_stays_within_bounds
  validate :path_present_for_path_shapes
  validate :frame_range_is_ordered
  validate :video_targets_declare_a_frame_rate
  validate :time_shape_carries_a_frame

  before_validation :apply_default_style

  scope :temporal, -> { where.not(start_frame: nil) }
  scope :spatial, -> { where.not(shape: %w[pin time]) }

  # Annotations whose region overlaps the given normalised rectangle. Used to
  # ask "does the pixel-diff between two versions intersect this feedback?".
  #
  # @param x [Float] @param y [Float] @param w [Float] @param h [Float]
  # @return [ActiveRecord::Relation]
  scope :overlapping, ->(x, y, w, h) {
    where("bbox_x <= ? AND bbox_x + bbox_w >= ? AND bbox_y <= ? AND bbox_y + bbox_h >= ?",
          x + w, x, y + h, y)
  }

  # @return [Boolean] true when this target covers a span of video rather than an instant
  def range?
    start_frame.present? && end_frame.present? && end_frame > start_frame
  end

  # @return [Float, nil] start position in seconds
  def start_seconds
    frames_to_seconds(start_frame)
  end

  # @return [Float, nil] end position in seconds
  def end_seconds
    frames_to_seconds(end_frame)
  end

  # @return [String, nil] the start position as SMPTE timecode, e.g. "00:01:23:11"
  def start_timecode
    frames_to_timecode(start_frame)
  end

  # @return [String, nil] the end position as SMPTE timecode
  def end_timecode
    frames_to_timecode(end_frame)
  end

  # Converts a frame number to an SMPTE timecode string.
  #
  # Handles NTSC drop-frame timebases (29.97 / 59.94 fps), where two frame
  # *numbers* are skipped at the start of every minute except every tenth
  # minute, keeping wall-clock and timecode aligned. Without this correction a
  # 29.97 fps timecode drifts by ~3.6 seconds per hour.
  #
  # @param frame [Integer, nil]
  # @return [String, nil] "HH:MM:SS:FF" (or "HH:MM:SS;FF" for drop-frame)
  def frames_to_timecode(frame)
    return nil if frame.blank? || fps.blank?

    rate = fps.to_f
    nominal = rate.round
    return nil if nominal.zero?

    adjusted = drop_frame ? apply_drop_frame_correction(frame.to_i, rate) : frame.to_i

    frames    = adjusted % nominal
    total_sec = adjusted / nominal
    seconds   = total_sec % 60
    minutes   = (total_sec / 60) % 60
    hours     = total_sec / 3600

    separator = drop_frame ? ";" : ":"
    format("%02d:%02d:%02d#{separator}%02d", hours, minutes, seconds, frames)
  end

  private

  def apply_default_style
    self.style = DEFAULT_STYLE.merge(style.presence || {})
  end

  def frames_to_seconds(frame)
    return nil if frame.blank? || fps.blank? || fps.to_f.zero?

    (frame.to_i / fps.to_f).round(4)
  end

  # Renumbers a frame count so that plain HH:MM:SS:FF arithmetic yields correct
  # drop-frame timecode. Standard SMPTE algorithm: skip `d` frame numbers at
  # each minute boundary, except on every tenth minute.
  def apply_drop_frame_correction(frame, rate)
    dropped_per_minute = (rate * 0.066666).round # 2 @ 29.97, 4 @ 59.94
    return frame if dropped_per_minute.zero?

    nominal          = rate.round
    frames_per_10min = (rate * 600).round
    frames_per_min   = (nominal * 60) - dropped_per_minute

    ten_minute_blocks = frame / frames_per_10min
    remainder         = frame % frames_per_10min

    correction = dropped_per_minute * 9 * ten_minute_blocks
    if remainder > dropped_per_minute
      correction += dropped_per_minute * ((remainder - dropped_per_minute) / frames_per_min)
    end

    frame + correction
  end

  def bbox_stays_within_bounds
    return if [ bbox_x, bbox_y, bbox_w, bbox_h ].any?(&:nil?)

    errors.add(:bbox_w, "extends beyond the right edge of the media") if bbox_x + bbox_w > 1.0001
    errors.add(:bbox_h, "extends beyond the bottom edge of the media") if bbox_y + bbox_h > 1.0001
  end

  def path_present_for_path_shapes
    return unless PATH_REQUIRED_SHAPES.include?(shape)
    return if svg_path.present?

    errors.add(:svg_path, "is required for a '#{shape}' annotation")
  end

  def frame_range_is_ordered
    return if start_frame.blank? || end_frame.blank?
    return if end_frame >= start_frame

    errors.add(:end_frame, "must not be before start_frame")
  end

  # Without an fps we cannot render a timecode or seek accurately, so a
  # temporal annotation with no frame rate is meaningless.
  def video_targets_declare_a_frame_rate
    return if start_frame.blank?
    return if fps.present?

    errors.add(:fps, "is required when a frame position is given")
  end

  # A +time+ target has no spatial extent, so a frame is the only thing that
  # locates it. Without one it would be invisible everywhere — not drawn on the
  # overlay (by design) and absent from the scrubber's marker track.
  def time_shape_carries_a_frame
    return unless shape == "time"
    return if start_frame.present?

    errors.add(:start_frame, "is required for a 'time' annotation")
  end
end
