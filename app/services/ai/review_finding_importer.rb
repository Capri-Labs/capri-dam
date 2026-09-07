module Ai
  # Turns findings returned by the AI gateway into real annotated comments.
  #
  # WHY FINDINGS BECOME ORDINARY THREADS
  # ------------------------------------
  # A finding is stored as a {CommentThread} + {Comment} + {AnnotationTarget},
  # exactly like a human remark, rather than in a parallel "suggestions" table.
  # Everything already built for review — normalised coordinates, version
  # binding, region-diff across versions, W3C export, the contact sheet — then
  # applies to machine output for free. A separate table would need all of it
  # reimplemented, and the two would drift.
  #
  # What separates a suggestion from feedback is {CommentThread#suggestion_state},
  # which starts +pending+ and hides the thread from every listing until a human
  # accepts it.
  #
  # TRUST BOUNDARY
  # --------------
  # The gateway is a separate service, so its payload is treated as untrusted
  # input: every field is validated or dropped, coordinates are clamped into
  # the unit square, and the body is length-capped. A malformed finding is
  # skipped rather than aborting the import — one bad shape should not discard
  # nine good findings.
  class ReviewFindingImporter
    # Anything below this is noise: a model that is unsure whether it saw a
    # problem produces reviewer fatigue, and a triage queue nobody reads is
    # worse than no queue.
    MIN_CONFIDENCE = 0.35

    # A single run that floods the queue is almost always a misconfigured
    # prompt rather than a genuinely terrible asset.
    MAX_FINDINGS = 50

    Result = Struct.new(:imported, :skipped, :errors, keyword_init: true)

    # @param review [AiReview]
    def initialize(review)
      @review = review
      @asset = review.asset
      @version = review.asset_version || review.asset.try(:active_version)
    end

    # @param findings [Array<Hash>] raw findings from the gateway
    # @return [Result]
    def import(findings)
      list = Array(findings).first(MAX_FINDINGS)
      imported = 0
      skipped = 0
      errors = []

      # One transaction for the whole run: a half-imported review would leave
      # the reviewer triaging an incomplete picture with no way to tell.
      ActiveRecord::Base.transaction do
        list.each_with_index do |raw, index|
          case create_finding(raw)
          when :created then imported += 1
          else skipped += 1
          end
        rescue ActiveRecord::RecordInvalid => e
          skipped += 1
          errors << "finding #{index}: #{e.record.errors.full_messages.to_sentence}"
        end

        @review.complete!(imported)
      end

      Result.new(imported: imported, skipped: skipped, errors: errors)
    end

    private

    # @return [Symbol] +:created+ or +:skipped+
    def create_finding(raw)
      data = normalise(raw)
      return :skipped if data.nil?

      thread = @asset.comment_threads.create!(
        ai_review: @review,
        origin_version: @version,
        status: "open",
        # Machine output is internal until a human decides otherwise. A
        # guest-visible default would put an unreviewed guess in front of a
        # client.
        visibility: "internal",
        suggestion_state: "pending",
      )

      comment = thread.comments.create!(
        body: data[:body],
        asset_version: @version,
        agent_type: "software",
        agent_name: @review.ai_model_name.presence || "Review assistant",
        confidence: data[:confidence],
        # W3C: "assessing" is the motivation for a quality judgement, which is
        # what a guideline check is, as opposed to a passing remark.
        motivation: "assessing",
      )

      data[:annotations].each do |annotation|
        comment.annotation_targets.create!(annotation)
      end

      :created
    end

    # Validates and coerces one raw finding. Returns nil when the finding is
    # unusable.
    #
    # @return [Hash, nil]
    def normalise(raw)
      data = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
      data = data.with_indifferent_access

      body = build_body(data)
      return nil if body.blank?

      confidence = data[:confidence].presence&.to_f
      # An absent confidence is treated as unknown, not as certain: a model
      # that declines to score itself should not outrank one that does.
      return nil if confidence && confidence < MIN_CONFIDENCE

      {
        body: body,
        confidence: confidence&.clamp(0.0, 1.0),
        annotations: Array(data[:annotations]).filter_map { |a| annotation_attributes(a) },
      }
    end

    # The gateway may send a structured finding (title + detail + rule) or a
    # plain message. Both collapse to a readable body, because the reviewer
    # reads prose, not JSON.
    def build_body(data)
      parts = [
        data[:title].presence,
        data[:detail].presence || data[:message].presence || data[:body].presence,
      ].compact

      body = parts.join("\n\n")
      rule = data[:rule].presence || data.dig(:meta, :rule).presence
      body = "#{body}\n\nGuideline: #{rule}" if rule.present?

      body.to_s.strip.truncate(Comment::MAX_BODY_LENGTH)
    end

    # @return [Hash, nil] attributes for an {AnnotationTarget}, or nil if unusable
    def annotation_attributes(raw)
      data = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
      data = data.with_indifferent_access

      shape = data[:shape].presence
      shape = "rect" unless AnnotationTarget::SHAPES.include?(shape)

      media_type = data[:media_type].presence
      media_type = default_media_type unless AnnotationTarget::MEDIA_TYPES.include?(media_type)

      bbox = (data[:bbox] || {}).with_indifferent_access
      x = clamp_unit(bbox[:x])
      y = clamp_unit(bbox[:y])
      # Width and height are additionally clamped so that x+w never exceeds 1,
      # which the database CHECK enforces — a model that reports a box running
      # off the right edge would otherwise abort the whole import.
      w = clamp_unit(bbox[:w], max: 1.0 - x)
      h = clamp_unit(bbox[:h], max: 1.0 - y)

      # A path-only shape with no path cannot be drawn.
      svg_path = data[:svg_path].presence
      return nil if AnnotationTarget::PATH_REQUIRED_SHAPES.include?(shape) && svg_path.blank?

      {
        media_type: media_type,
        shape: shape,
        bbox_x: x,
        bbox_y: y,
        bbox_w: w,
        bbox_h: h,
        svg_path: svg_path,
        start_frame: safe_frame(data.dig(:video, :start_frame)),
        end_frame: safe_frame(data.dig(:video, :end_frame)),
        fps: data.dig(:video, :fps),
        label: data[:label].presence&.truncate(120),
        # Machine findings are drawn in a distinct colour so a reviewer can
        # tell at a glance which marks on the frame are not a colleague's.
        style: { "stroke_color" => "#a855f7" },
      }.compact
    end

    def default_media_type
      content_type = @asset.properties&.dig("content_type").to_s
      return "video" if content_type.start_with?("video/")
      return "document" if content_type == "application/pdf"

      "image"
    end

    def clamp_unit(value, max: 1.0)
      value.to_f.clamp(0.0, [ max, 0.0 ].max)
    end

    def safe_frame(value)
      return nil if value.blank?

      frame = value.to_i
      frame.negative? ? nil : frame
    end
  end
end
