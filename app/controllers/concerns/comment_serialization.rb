# Shared JSON shaping for the commenting/annotation endpoints
# ({Api::V1::CommentThreadsController} and {Api::V1::CommentsController}), so a
# thread has exactly one representation no matter which endpoint returned it.
#
# Geometry is emitted already normalised (0..1, upper-left origin) and the SVG
# path in its <tt>viewBox="0 0 1 1"</tt> space, so the React overlay can render
# it straight into an <tt><svg></tt> with no coordinate conversion. Video
# positions are emitted three ways — frames (authoritative), seconds (for
# +video.currentTime+ seeking) and SMPTE timecode (for display) — all derived
# from the single stored frame number.
module CommentSerialization
  extend ActiveSupport::Concern

  private

  # @param thread [CommentThread]
  # @param include_comments [Boolean] embed the full comment tree
  # @return [Hash]
  def serialize_thread(thread, include_comments: true)
    payload = {
      id: thread.id,
      asset_id: thread.asset_id,
      status: thread.status,
      visibility: thread.visibility,
      closed: thread.closed?,
      origin_version: serialize_version_stub(thread.origin_version),
      created_by: serialize_comment_user(thread.created_by),
      resolved_at: thread.resolved_at,
      resolved_by: serialize_comment_user(thread.resolved_by),
      comment_count: thread.comments.active.count,
      created_at: thread.created_at,
      updated_at: thread.updated_at,
    }

    payload[:comments] = thread.comments.active.roots.chronological.map { |c| serialize_comment(c) } if include_comments

    payload
  end

  # @param comment [Comment]
  # @param include_replies [Boolean]
  # @return [Hash]
  def serialize_comment(comment, include_replies: true)
    payload = {
      id: comment.id,
      comment_thread_id: comment.comment_thread_id,
      parent_comment_id: comment.parent_comment_id,
      body: comment.body,
      motivation: comment.motivation,
      agent_type: comment.agent_type,
      agent_name: comment.agent_name,
      confidence: comment.confidence&.to_f,
      author: serialize_comment_user(comment.author),
      author_display_name: comment.author_display_name,
      asset_version: serialize_version_stub(comment.asset_version),
      edited: comment.edited?,
      edited_at: comment.edited_at,
      created_at: comment.created_at,
      annotations: comment.annotation_targets.map { |a| serialize_annotation(a, thread_id: comment.comment_thread_id) },
    }

    payload[:replies] = comment.replies.active.map { |r| serialize_comment(r, include_replies: false) } if include_replies

    payload
  end

  # @param target [AnnotationTarget]
  # @param thread_id [String, nil] passed down from the owning comment so the
  #   overlay can link a marker back to its thread without another query
  # @return [Hash]
  def serialize_annotation(target, thread_id: nil)
    {
      id: target.id,
      comment_id: target.comment_id,
      thread_id: thread_id,
      media_type: target.media_type,
      shape: target.shape,
      # Normalised 0..1, upper-left origin.
      bbox: { x: target.bbox_x, y: target.bbox_y, w: target.bbox_w, h: target.bbox_h },
      # Geometry-only path in a viewBox="0 0 1 1" space.
      svg_path: target.svg_path,
      video: serialize_temporal(target),
      page: target.page,
      text: {
        exact: target.text_exact,
        prefix: target.text_prefix,
        suffix: target.text_suffix,
        start: target.text_start,
        end: target.text_end,
      }.compact.presence,
      # The media as it was when annotated — lets a later phase re-project this
      # geometry onto a rotated/cropped version instead of silently misplacing
      # the marker.
      source: {
        width: target.source_width,
        height: target.source_height,
        rotation: target.source_rotation,
        crop: target.source_crop,
      },
      style: target.style,
      label: target.label,
    }
  end

  # Emits a video position in all three timebases the UI needs.
  # @param target [AnnotationTarget]
  # @return [Hash, nil]
  def serialize_temporal(target)
    return nil if target.start_frame.blank?

    {
      start_frame: target.start_frame,
      end_frame: target.end_frame,
      fps: target.fps&.to_f,
      drop_frame: target.drop_frame,
      range: target.range?,
      start_seconds: target.start_seconds,
      end_seconds: target.end_seconds,
      start_timecode: target.start_timecode,
      end_timecode: target.end_timecode,
    }
  end

  # @param user [User, nil]
  # @return [Hash, nil]
  def serialize_comment_user(user)
    return nil if user.blank?

    { id: user.id, email: user.email, name: user.full_name }
  end

  # @param version [AssetVersion, nil]
  # @return [Hash, nil]
  def serialize_version_stub(version)
    return nil if version.blank?

    { id: version.id, version_number: version.version_number, action_type: version.action_type }
  end

  # Whitelists and normalises one incoming annotation payload.
  #
  # The client sends geometry as a nested +bbox+ object; the database stores
  # flat columns so they can be indexed for region-overlap queries.
  #
  # @param raw [ActionController::Parameters, Hash]
  # @return [Hash]
  def annotation_attributes_from(raw)
    permitted = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
    permitted = permitted.with_indifferent_access
    bbox      = (permitted[:bbox] || {}).with_indifferent_access

    {
      media_type: permitted[:media_type].presence || "image",
      shape: permitted[:shape].presence || "pin",
      bbox_x: bbox[:x].to_f,
      bbox_y: bbox[:y].to_f,
      bbox_w: bbox[:w].to_f,
      bbox_h: bbox[:h].to_f,
      svg_path: permitted[:svg_path],
      start_frame: permitted.dig(:video, :start_frame),
      end_frame: permitted.dig(:video, :end_frame),
      fps: permitted.dig(:video, :fps),
      drop_frame: ActiveModel::Type::Boolean.new.cast(permitted.dig(:video, :drop_frame)) || false,
      page: permitted[:page],
      text_exact: permitted.dig(:text, :exact),
      text_prefix: permitted.dig(:text, :prefix),
      text_suffix: permitted.dig(:text, :suffix),
      text_start: permitted.dig(:text, :start),
      text_end: permitted.dig(:text, :end),
      source_width: permitted.dig(:source, :width),
      source_height: permitted.dig(:source, :height),
      source_rotation: permitted.dig(:source, :rotation).presence || 0,
      source_crop: permitted.dig(:source, :crop),
      style: permitted[:style].presence || {},
      label: permitted[:label],
    }.compact
  end
end
