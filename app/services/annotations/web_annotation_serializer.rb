# Emits Capri review data as W3C Web Annotation Data Model JSON-LD.
#
# WHY THIS EXISTS
# ---------------
# Review feedback is the one part of a DAM that most needs to leave the DAM.
# Agencies run approvals in one tool, brand teams archive sign-off in another,
# and a proofing vendor may be contractually the system of record. A
# proprietary comment payload makes all of that a bespoke integration. The
# W3C Web Annotation Data Model (https://www.w3.org/TR/annotation-model/) is
# the interchange format for exactly this, and it is what IIIF viewers,
# Hypothesis and Mirador already speak.
#
# THE SCHEMA WAS ALREADY BUILT FOR IT
# -----------------------------------
# This is a mapping, not a translation. +Comment#motivation+ is already the
# W3C §3.3.5 motivation vocabulary; +agent_type+ already mirrors the
# Person/Software agent classes; +AnnotationTarget+'s normalised bbox and
# geometry-only +svg_path+ were chosen to mirror the FragmentSelector /
# SvgSelector split, and its +text_exact+/+text_prefix+/+text_suffix+ and
# +text_start+/+text_end+ columns are TextQuoteSelector and
# TextPositionSelector field-for-field.
#
# LOSSLESS ROUND-TRIP WITHOUT BREAKING THE STANDARD
# -------------------------------------------------
# Pure W3C would throw away things Capri needs on the way back: which *shape*
# a region was drawn as (a rect and an ellipse have the same bbox), stroke
# styling, the exact frame rate, drop-frame flag, and thread grouping. Those
# are emitted under a namespaced +capri:+ extension, which the Web Annotation
# model explicitly permits. A third-party consumer sees a valid, complete
# annotation and ignores the extension; Capri reads the extension back and
# reconstructs the original exactly. Neither audience is compromised for the
# other.
module Annotations
  class WebAnnotationSerializer
    W3C_CONTEXT   = "http://www.w3.org/ns/anno.jsonld".freeze
    CAPRI_CONTEXT = { "capri" => "https://capri-labs.dev/ns/annotation#" }.freeze

    # Shapes whose geometry a bounding box alone cannot express, so they must
    # carry an SvgSelector to survive the trip.
    SVG_BEARING_SHAPES = %w[ellipse arrow line freehand].freeze

    # @param asset [Asset]
    # @param threads [ActiveRecord::Relation<CommentThread>, Array<CommentThread>]
    # @param base_url [String] absolute origin used to mint annotation and target IRIs
    def initialize(asset:, threads:, base_url: nil)
      @asset    = asset
      @threads  = threads
      @base_url = base_url.presence&.chomp("/")
    end

    # A whole asset's review history as a W3C AnnotationPage.
    #
    # AnnotationPage rather than AnnotationCollection because the export is a
    # single complete document, not a paged, dereferenceable collection — the
    # model reserves Collection for the latter.
    #
    # @return [Hash]
    def as_page
      {
        "@context" => [ W3C_CONTEXT, CAPRI_CONTEXT ],
        "id"       => "#{asset_iri}/annotations",
        "type"     => "AnnotationPage",
        "label"    => @asset.title,
        "capri:generated" => Time.current.utc.iso8601,
        "capri:asset"     => asset_extension,
        "items"    => annotations,
      }
    end

    # Every comment across every thread, flattened. The Web Annotation model
    # has no thread primitive, so grouping is preserved two ways: the standard
    # way, via each reply's +motivation+ and its target pointing at the parent
    # annotation, and the exact way, via +capri:threadId+.
    #
    # @return [Array<Hash>]
    def annotations
      @threads.flat_map do |thread|
        thread.comments.active.chronological.map { |comment| annotation_for(comment, thread) }
      end
    end

    # @param comment [Comment]
    # @param thread [CommentThread]
    # @return [Hash]
    def annotation_for(comment, thread)
      payload = {
        "@context"   => W3C_CONTEXT,
        "id"         => comment_iri(comment),
        "type"       => "Annotation",
        "motivation" => comment.motivation,
        "created"    => comment.created_at.utc.iso8601,
        "creator"    => creator_for(comment),
        "body"       => body_for(comment),
        "target"     => target_for(comment),
      }

      payload["modified"] = comment.edited_at.utc.iso8601 if comment.edited_at.present?
      payload.merge(comment_extension(comment, thread))
    end

    private

    def asset_iri
      "#{@base_url}/api/v1/assets/#{@asset.id}"
    end

    def comment_iri(comment)
      "#{@base_url}/api/v1/comments/#{comment.id}"
    end

    def thread_iri(thread)
      "#{@base_url}/api/v1/comment_threads/#{thread.id}"
    end

    # The body is the reviewer's words. TextualBody with an explicit format is
    # the model's recommendation for plain-text commentary (§4.1).
    def body_for(comment)
      {
        "type"    => "TextualBody",
        "value"   => comment.body,
        "format"  => "text/plain",
        "purpose" => comment.motivation,
      }
    end

    # +Software+ rather than +Person+ for machine-generated review notes, which
    # is precisely the distinction the model's agent classes exist to draw, and
    # keeps an AI assistant's findings honestly labelled downstream.
    def creator_for(comment)
      if comment.agent_type == "software"
        { "type" => "Software", "name" => comment.agent_name.presence || "Assistant" }.compact
      else
        {
          "id"    => comment.author_id ? "#{@base_url}/api/v1/users/#{comment.author_id}" : nil,
          "type"  => "Person",
          "name"  => comment.author&.full_name.presence || comment.author_display_name,
          "email" => comment.author&.email,
        }.compact
      end
    end

    # A reply targets the comment it answers, not the media. That is what makes
    # threading legible to a consumer that has never heard of Capri.
    def target_for(comment)
      return comment_iri(comment.parent_comment) if comment.reply?

      selectors = comment.annotation_targets.flat_map { |t| selectors_for(t) }
      source    = version_iri(comment.asset_version) || asset_iri

      return source if selectors.empty?

      {
        "source"   => source,
        "type"     => target_dctype(comment),
        "selector" => selectors.one? ? selectors.first : selectors,
      }.compact
    end

    def version_iri(version)
      return nil if version.blank?

      "#{asset_iri}/versions/#{version.id}"
    end

    # dctypes classes let a consumer pick a renderer without fetching the file.
    def target_dctype(comment)
      case comment.annotation_targets.first&.media_type
      when "video"    then "Video"
      when "document" then "Text"
      when "image"    then "Image"
      end
    end

    # One annotation target can need several selectors at once — a region *and*
    # a moment in a video, for instance. They are emitted as a list, which the
    # model treats as "all of these apply".
    #
    # @param target [AnnotationTarget]
    # @return [Array<Hash>]
    def selectors_for(target)
      selectors = []

      # A +time+ target has no spatial extent at all, so a region would be a
      # lie. A pin has no area either but still needs locating, so it is
      # emitted as a zero-size fragment at its point.
      selectors << fragment_selector(target) unless target.shape == "time"
      selectors << svg_selector(target)      if target.svg_path.present? && SVG_BEARING_SHAPES.include?(target.shape)
      selectors << temporal_selector(target) if target.start_frame.present?
      selectors << page_selector(target)     if target.page.present?
      selectors << text_quote_selector(target)    if target.text_exact.present?
      selectors << text_position_selector(target) if target.text_start.present?

      selectors.compact
    end

    # W3C Media Fragments percent form. Percent, not pixels, because the stored
    # geometry is resolution-independent by design — emitting pixels would bind
    # the export to whichever rendition happened to be on screen.
    def fragment_selector(target)
      {
        "type"         => "FragmentSelector",
        "conformsTo"   => "http://www.w3.org/TR/media-frags/",
        "value"        => format(
          "xywh=percent:%<x>g,%<y>g,%<w>g,%<h>g",
          x: percent(target.bbox_x), y: percent(target.bbox_y),
          w: percent(target.bbox_w), h: percent(target.bbox_h)
        ),
        "capri:shape"  => target.shape,
        "capri:style"  => target.style,
        "capri:label"  => target.label,
        "capri:source" => source_extension(target),
      }.compact
    end

    # The stored path is geometry-only in a viewBox="0 0 1 1" space; an
    # SvgSelector's value must be a standalone SVG document, so it is wrapped
    # here rather than stored wrapped. Styling stays out of the SVG, per the
    # model's own recommendation, and travels in the capri: extension.
    def svg_selector(target)
      {
        "type"  => "SvgSelector",
        "value" => %(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1">) +
                   %(<path d="#{ERB::Util.html_escape(target.svg_path)}"/></svg>),
      }
    end

    # npt (normal play time) seconds, the Media Fragments default. Seconds are
    # what the standard speaks; the authoritative frame numbers and the frame
    # rate ride along in the extension so frame accuracy is not lost on the way
    # back in.
    def temporal_selector(target)
      value = if target.range?
                "t=npt:#{target.start_seconds},#{target.end_seconds}"
      else
                "t=npt:#{target.start_seconds}"
      end

      {
        "type"                => "FragmentSelector",
        "conformsTo"          => "http://www.w3.org/TR/media-frags/",
        "value"               => value,
        "capri:startFrame"    => target.start_frame,
        "capri:endFrame"      => target.end_frame,
        "capri:fps"           => target.fps&.to_f,
        "capri:dropFrame"     => target.drop_frame,
        "capri:startTimecode" => target.start_timecode,
        "capri:endTimecode"   => target.end_timecode,
      }.compact
    end

    def page_selector(target)
      {
        "type"       => "FragmentSelector",
        "conformsTo" => "http://www.w3.org/TR/media-frags/",
        "value"      => "page=#{target.page}",
      }
    end

    # Prefix and suffix are what let a quote be relocated after the surrounding
    # document shifts — the whole point of TextQuoteSelector over a raw offset.
    def text_quote_selector(target)
      {
        "type"   => "TextQuoteSelector",
        "exact"  => target.text_exact,
        "prefix" => target.text_prefix,
        "suffix" => target.text_suffix,
      }.compact
    end

    def text_position_selector(target)
      { "type" => "TextPositionSelector", "start" => target.text_start, "end" => target.text_end }.compact
    end

    # The media's dimensions and orientation when the mark was made, so a
    # consumer can tell a re-crop from a re-export.
    def source_extension(target)
      {
        "width"    => target.source_width,
        "height"   => target.source_height,
        "rotation" => target.source_rotation,
        "crop"     => target.source_crop,
      }.compact.presence
    end

    def asset_extension
      { "id" => @asset.id, "title" => @asset.title }.compact
    end

    # Everything Capri needs on re-import that the standard has no place for.
    def comment_extension(comment, thread)
      {
        "capri:commentId" => comment.id,
        "capri:threadId"  => thread.id,
        "capri:thread"    => {
          "id"         => thread.id,
          "iri"        => thread_iri(thread),
          "status"     => thread.status,
          "visibility" => thread.visibility,
          "resolvedAt" => thread.resolved_at&.utc&.iso8601,
        }.compact,
        "capri:agentType"  => comment.agent_type,
        "capri:confidence" => comment.confidence&.to_f,
        "capri:versionId"  => comment.asset_version_id,
        "capri:parentId"   => comment.parent_comment_id,
      }.compact
    end

    def percent(value)
      (value.to_f * 100).round(4)
    end
  end
end
