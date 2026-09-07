# Ingests a W3C Web Annotation document back into Capri threads and comments.
#
# The mirror of {Annotations::WebAnnotationSerializer}. Two very different
# documents have to be handled by the same code path:
#
#   * one Capri produced, which carries the +capri:+ extension and can be
#     rebuilt exactly — shape, styling, frame rate, thread grouping and all;
#   * one from a third party (a IIIF viewer, Hypothesis, a proofing vendor),
#     which has only the standard vocabulary. Everything Capri needs beyond
#     that is inferred: the shape from which selectors are present, the frame
#     numbers from npt seconds and a supplied frame rate.
#
# ATTRIBUTION IS DELIBERATELY NOT HONOURED
# ----------------------------------------
# An incoming document names a creator, but trusting it would make the review
# trail forgeable: anyone who can import could hand-edit a file and manufacture
# an approval from a colleague. Every imported comment is therefore authored by
# the authenticated user performing the import, who is accountable for it, and
# the claimed original creator is retained as untrusted provenance in
# +Comment#import_source+.
#
# IMPORT IS ADDITIVE, NEVER DESTRUCTIVE
# -------------------------------------
# Re-importing a document Capri exported must not duplicate the conversation,
# and must not silently overwrite whatever was said in the meantime. Comments
# whose +capri:commentId+ already exists are skipped rather than updated: an
# import is someone else's copy of the past, and it should not be able to
# rewrite the live thread.
module Annotations
  class WebAnnotationImporter
    class InvalidDocument < StandardError; end

    # A frame rate is needed to turn npt seconds back into authoritative frame
    # numbers. Capri-produced documents state it; third-party ones do not, and
    # a temporal annotation without one cannot be stored (AnnotationTarget
    # rejects it), so it is imported as a plain thread-level comment instead of
    # being dropped.
    SHAPE_FROM_SELECTORS = {
      svg:  "freehand",
      text: "highlight",
      time: "time",
      area: "rect",
      point: "pin",
    }.freeze

    Result = Struct.new(:threads_created, :comments_created, :skipped, :errors, keyword_init: true) do
      def to_h
        {
          threads_created: threads_created,
          comments_created: comments_created,
          skipped: skipped,
          errors: errors,
        }
      end
    end

    # @param asset [Asset] the asset the annotations are being attached to
    # @param document [Hash] a parsed AnnotationPage, Annotation, or bare array
    # @param user [User] the authenticated importer, who becomes the author
    # @param source_label [String, nil] where the file came from, for provenance
    # @param honour_status [Boolean] whether a document may assert that a thread
    #   arrived already resolved. Closing feedback is a lifecycle decision, so
    #   it is only honoured for a caller who could have closed it by hand.
    def initialize(asset:, document:, user:, source_label: nil, honour_status: false)
      @asset         = asset
      @document      = document
      @user          = user
      @source_label  = source_label.presence || "web-annotation-import"
      @honour_status = honour_status
      @result        = Result.new(threads_created: 0, comments_created: 0, skipped: 0, errors: [])
      # Maps an incoming annotation IRI to the Comment it became, so a reply
      # that targets it can be attached in the same pass.
      @by_iri        = {}
    end

    # @return [Result]
    def call
      items = extract_items(@document)
      raise InvalidDocument, "No annotations found in document" if items.empty?

      # Every annotation IRI in this document. A bare-string target is a reply
      # only when it names one of them; if it names anything else it is a
      # target *of the media itself*, which is a root comment. Matching against
      # the document is exact and works for any exporter's IRI scheme, whereas
      # guessing from the URL path only ever recognises Capri's own.
      @document_iris = items.filter_map { |item| item["id"].presence }.to_set

      ActiveRecord::Base.transaction do
        # Roots first: a reply can only be attached once its parent exists, and
        # a document is not obliged to list them in that order.
        roots, replies = items.partition { |item| reply_target_iri(item).blank? }
        roots.each   { |item| import_annotation(item) }
        replies.each { |item| import_annotation(item) }
      end

      @result
    end

    private

    # Accepts an AnnotationPage, an AnnotationCollection with an embedded
    # first page, a bare array, or a single Annotation — all four are shapes
    # real exporters emit.
    def extract_items(document)
      case document
      when Array then document
      when Hash
        return wrap(document["items"]) if document["items"].present?
        return extract_items(document["first"]) if document["first"].present?
        return [ document ] if document["type"].to_s.include?("Annotation")

        []
      else
        []
      end
    end

    def import_annotation(item)
      external_id = item["capri:commentId"].presence || item["id"].presence

      if already_imported?(item, external_id)
        @result.skipped += 1
        return
      end

      thread  = thread_for(item)
      comment = build_comment(item, thread)

      comment.save!
      @by_iri[item["id"]] = comment if item["id"].present?
      @result.comments_created += 1

      import_targets(item, comment)
    rescue ActiveRecord::RecordInvalid => e
      # One malformed annotation must not abort a 200-annotation import, but
      # the caller has to be told which ones failed and why.
      @result.errors << { id: item["id"], message: e.record.errors.full_messages.to_sentence }
      @result.skipped += 1
    end

    # A round-trip of Capri's own export must be a no-op, not a duplication.
    #
    # Scoped to *this* asset on purpose: a comment ID existing elsewhere in the
    # instance means the annotation was written about a different file, and
    # copying review notes from one asset onto another is a legitimate thing to
    # want. Only a re-import onto the same asset is a duplicate.
    #
    # Three identities are checked because an annotation can arrive by three
    # routes: as a live Capri comment (its own UUID), as something previously
    # imported here from Capri (the recorded capri_id), or as something
    # previously imported from a third party (the recorded IRI).
    def already_imported?(item, external_id)
      return false if external_id.blank?

      on_this_asset = Comment.joins(:comment_thread).where(comment_threads: { asset_id: @asset.id })
      capri_id      = item["capri:commentId"].presence
      iri           = item["id"].presence

      return true if capri_id.present? && on_this_asset.where(comments: { id: capri_id }).exists?

      conditions = []
      values     = []
      if capri_id.present?
        conditions << "comments.import_source ->> 'capri_id' = ?"
        values << capri_id.to_s
      end
      if iri.present?
        conditions << "comments.import_source ->> 'iri' = ?"
        values << iri.to_s
      end
      return false if conditions.empty?

      # Explicitly parenthesised: without it the OR could associate past the
      # asset scope and match comments on other assets.
      on_this_asset.where("(#{conditions.join(" OR ")})", *values).exists?
    end

    # Grouping, in descending order of confidence:
    #   1. the thread the annotation says it belongs to, if it still exists here
    #   2. the thread its parent comment is already in (for replies)
    #   3. a thread created for this import, shared by everything that quoted
    #      the same capri:threadId
    def thread_for(item)
      parent = parent_comment_for(item)
      return parent.comment_thread if parent

      declared = item["capri:threadId"].presence
      if declared.present?
        existing = CommentThread.find_by(id: declared, asset_id: @asset.id)
        return existing if existing

        @threads_by_external ||= {}
        return @threads_by_external[declared] ||= create_thread(item)
      end

      create_thread(item)
    end

    def create_thread(item)
      declared = item.dig("capri:thread") || {}

      thread = CommentThread.create!(
        asset: @asset,
        created_by: @user,
        origin_version_id: version_id_for(item),
        status: imported_status(declared),
        # Visibility is always forced to internal: making a thread visible to
        # external guests is a disclosure decision, and an uploaded file must
        # not be able to make it.
        visibility: "internal",
      )

      @result.threads_created += 1
      thread
    end

    # Knowing a note arrived already resolved is a real reason to import a
    # completed review, so the claim is honoured — but only for a caller who
    # holds the permission needed to resolve a thread by hand. Otherwise an
    # uploaded file could silently close outstanding feedback.
    def imported_status(declared)
      return "open" unless @honour_status

      CommentThread::STATUSES.include?(declared["status"]) ? declared["status"] : "open"
    end

    def build_comment(item, thread)
      Comment.new(
        comment_thread: thread,
        asset_version_id: version_id_for(item),
        parent_comment: parent_comment_for(item),
        body: body_text(item),
        motivation: motivation_for(item),
        author: @user,
        agent_type: "person",
        import_source: provenance(item),
      )
    end

    # The body may be a plain string, a TextualBody, or a list of bodies
    # (a tag plus a comment, say). All three appear in the wild.
    def body_text(item)
      value = wrap(item["body"]).filter_map do |body|
        case body
        when String then body
        when Hash   then body["value"] || body["chars"]
        end
      end.join("\n\n")

      # A body-less annotation is legal W3C (a bare highlight, for instance),
      # but a Capri comment requires text, so it gets a placeholder rather than
      # being dropped — the geometry the reviewer drew is still worth keeping.
      value.presence || "(imported annotation with no body)"
    end

    # Array() splats a Hash into [key, value] pairs, which silently destroys a
    # lone TextualBody. Every "one or many" field in this format needs this.
    def wrap(value)
      case value
      when nil   then []
      when Array then value
      else [ value ]
      end
    end

    def motivation_for(item)
      declared = wrap(item["motivation"]).first.to_s.sub(/\Aoa:/, "")
      return declared if Comment::MOTIVATIONS.include?(declared)

      # A reply is a reply even when the source tool did not say so.
      reply_target_iri(item).present? ? "replying" : "commenting"
    end

    def provenance(item)
      {
        "iri"         => item["id"],
        "capri_id"    => item["capri:commentId"],
        "source"      => @source_label,
        "imported_at" => Time.current.utc.iso8601,
        "imported_by" => @user.id,
        # Explicitly "claimed": this is what the file asserted, not what Capri
        # verified, and nothing should treat it as an identity.
        "claimed_creator" => claimed_creator(item),
        "claimed_created_at" => item["created"],
      }.compact
    end

    def claimed_creator(item)
      creator = item["creator"]
      case creator
      when String then { "id" => creator }
      when Hash   then creator.slice("id", "type", "name", "email").presence
      end
    end

    def version_id_for(item)
      declared = item["capri:versionId"].presence
      return declared if declared.present? && @asset.asset_versions.where(id: declared).exists?

      @asset.asset_versions.order(version_number: :desc).first&.id
    end

    def reply_target_iri(item)
      declared = item["capri:parentId"].presence
      return declared if declared.present?

      target = item["target"]
      return nil unless target.is_a?(String)

      # Names another annotation in this document => a reply. Names anything
      # else (the media file, a canvas) => a comment on the media itself.
      return target if @document_iris&.include?(target)

      # An IRI Capri minted is recognisable even when the annotation it points
      # at was not included in the file — a partial export of one thread, say.
      target.include?("/comments/") ? target : nil
    end

    def parent_comment_for(item)
      iri = reply_target_iri(item)
      return nil if iri.blank?

      # Scoped to this asset throughout. An IRI carries a UUID that may well
      # identify a live comment elsewhere in the instance, and resolving to it
      # would silently graft the reply onto a different asset's conversation.
      on_this_asset = Comment.joins(:comment_thread).where(comment_threads: { asset_id: @asset.id })
      uuid          = uuid_from(iri)

      resolved = @by_iri[iri] ||
                 (uuid && on_this_asset.find_by(comments: { id: uuid })) ||
                 on_this_asset.find_by("comments.import_source ->> 'iri' = ?", iri.to_s) ||
                 (uuid && on_this_asset.find_by("comments.import_source ->> 'capri_id' = ?", uuid))

      # Threading is single-level, so a reply to a reply is re-parented onto
      # the root rather than rejected — losing the comment would be worse than
      # flattening it.
      resolved&.reply? ? resolved.parent_comment : resolved
    end

    def uuid_from(iri)
      iri.to_s[/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i]
    end

    # ── Targets ───────────────────────────────────────────────────────────────

    def import_targets(item, comment)
      selectors = selectors_from(item["target"])
      return if selectors.empty?

      attributes = target_attributes(selectors)
      return if attributes.blank?

      comment.annotation_targets.create!(attributes)
    rescue ActiveRecord::RecordInvalid => e
      # The comment itself is already saved and is worth keeping even if its
      # geometry could not be reconstructed — text feedback without a marker
      # still carries the reviewer's meaning.
      @result.errors << { id: item["id"], message: "Annotation geometry skipped: #{e.record.errors.full_messages.to_sentence}" }
    end

    def selectors_from(target)
      return [] unless target.is_a?(Hash)

      # NOT Array(): a lone selector is a Hash, and Array(hash) splats it into
      # [key, value] pairs rather than wrapping it. The model permits both a
      # single selector and a list, so both shapes must be handled.
      selector = target["selector"] || target["hasSelector"]
      case selector
      when Hash  then [ selector ]
      when Array then selector.flatten.select { |s| s.is_a?(Hash) }
      else []
      end
    end

    def target_attributes(selectors)
      area     = selectors.find { |s| fragment_value(s)&.start_with?("xywh=") }
      svg      = selectors.find { |s| s["type"].to_s.include?("Svg") }
      temporal = selectors.find { |s| fragment_value(s)&.start_with?("t=") }
      page     = selectors.find { |s| fragment_value(s)&.start_with?("page=") }
      quote    = selectors.find { |s| s["type"].to_s.include?("TextQuote") }
      position = selectors.find { |s| s["type"].to_s.include?("TextPosition") }

      bbox   = parse_xywh(fragment_value(area))
      timing = parse_temporal(temporal)

      # A temporal selector with no recoverable frame rate cannot be stored;
      # dropping the geometry keeps the comment rather than failing the import.
      return nil if temporal.present? && timing.blank? && bbox.blank?

      {
        media_type: media_type_for(timing, page, quote),
        shape: shape_for(area, svg, timing, quote),
        bbox_x: bbox&.dig(:x) || 0.0,
        bbox_y: bbox&.dig(:y) || 0.0,
        bbox_w: bbox&.dig(:w) || 0.0,
        bbox_h: bbox&.dig(:h) || 0.0,
        svg_path: svg_path_from(svg),
        page: parse_page(fragment_value(page)),
        text_exact: quote&.dig("exact"),
        text_prefix: quote&.dig("prefix"),
        text_suffix: quote&.dig("suffix"),
        text_start: position&.dig("start"),
        text_end: position&.dig("end"),
        label: area&.dig("capri:label"),
        style: area&.dig("capri:style").presence || {},
        source_width: area&.dig("capri:source", "width"),
        source_height: area&.dig("capri:source", "height"),
        source_rotation: area&.dig("capri:source", "rotation") || 0,
        source_crop: area&.dig("capri:source", "crop"),
      }.merge(timing || {}).compact
    end

    def fragment_value(selector)
      return nil unless selector.is_a?(Hash)
      return nil unless selector["type"].to_s.include?("Fragment")

      selector["value"].to_s
    end

    def media_type_for(timing, page, quote)
      return "video" if timing.present?
      return "document" if page.present? || quote.present?

      "image"
    end

    # A Capri export states the shape outright. For a third-party document it
    # has to be inferred from which selectors are present, which is why the
    # shape is round-tripped in the extension at all: an ellipse and a rect are
    # indistinguishable once reduced to a bounding box.
    def shape_for(area, svg, timing, quote)
      declared = area&.dig("capri:shape")
      return declared if AnnotationTarget::SHAPES.include?(declared)

      return SHAPE_FROM_SELECTORS[:svg]   if svg.present?
      return SHAPE_FROM_SELECTORS[:text]  if quote.present?
      return SHAPE_FROM_SELECTORS[:time]  if timing.present? && area.blank?
      return SHAPE_FROM_SELECTORS[:point] if area.present? && zero_area?(area)

      SHAPE_FROM_SELECTORS[:area]
    end

    def zero_area?(area)
      bbox = parse_xywh(fragment_value(area))
      bbox.present? && bbox[:w].zero? && bbox[:h].zero?
    end

    def svg_path_from(selector)
      value = selector&.dig("value").to_s
      return nil if value.blank?

      # Unwrap the <svg> envelope back to the bare geometry Capri stores. The
      # path is kept, not the wrapper, so styling cannot sneak in through it.
      value[/\sd="([^"]*)"/, 1]&.then { |d| CGI.unescapeHTML(d) }
    end

    # Media Fragments permits both "xywh=percent:..." and a bare pixel
    # "xywh=x,y,w,h". Only the percent form is unambiguous without knowing the
    # rendition, so pixel fragments are accepted only when the selector also
    # states the source dimensions to divide by.
    def parse_xywh(value)
      return nil if value.blank?

      match = value.match(/xywh=(?:(percent|pixel):)?\s*([\d.]+),\s*([\d.]+),\s*([\d.]+),\s*([\d.]+)/)
      return nil if match.blank?

      unit = match[1]
      nums = match[2..5].map(&:to_f)
      return nil unless unit == "percent" || unit.nil?

      # A bare fragment with values all <= 1 is already normalised; otherwise
      # it is a percentage.
      divisor = nums.all? { |n| n <= 1.0 } && unit.nil? ? 1.0 : 100.0

      x, y, w, h = nums.map { |n| (n / divisor).clamp(0.0, 1.0) }
      { x: x, y: y, w: [ w, 1.0 - x ].min, h: [ h, 1.0 - y ].min }
    end

    def parse_page(value)
      value.to_s[/page=(\d+)/, 1]&.to_i
    end

    # Frames are authoritative, seconds are the interchange form. A Capri
    # document restates the frames exactly; for anything else they are
    # reconstructed from npt seconds, which needs a frame rate — without one
    # the position cannot be stored at all.
    def parse_temporal(selector)
      return nil if selector.blank?

      fps = selector["capri:fps"]&.to_f
      fps = nil unless fps&.positive?

      start_frame = selector["capri:startFrame"]
      end_frame   = selector["capri:endFrame"]

      if start_frame.blank?
        return nil if fps.blank?

        seconds = fragment_value(selector).to_s[/t=(?:npt:)?([\d.]+)(?:,([\d.]+))?/, 1]
        finish  = fragment_value(selector).to_s[/t=(?:npt:)?[\d.]+,([\d.]+)/, 1]
        return nil if seconds.blank?

        start_frame = (seconds.to_f * fps).floor
        end_frame   = finish.present? ? (finish.to_f * fps).floor : nil
      end

      return nil if fps.blank?

      {
        start_frame: start_frame.to_i,
        end_frame: end_frame&.to_i,
        fps: fps,
        drop_frame: ActiveModel::Type::Boolean.new.cast(selector["capri:dropFrame"]) || false,
      }
    end
  end
end
