module Api
  module V1
    # Interchange for review data: export an asset's conversation as W3C Web
    # Annotation JSON-LD or as an annotated PDF sign-off sheet, and ingest a
    # W3C document back in.
    #
    # WHY EXPORT MATTERS
    # ------------------
    # Feedback is the part of a DAM that most needs to leave it. Approvals run
    # in agency tooling, archives live elsewhere, and a proofing vendor may be
    # the contractual system of record. Emitting the W3C Web Annotation Data
    # Model (https://www.w3.org/TR/annotation-model/) rather than a proprietary
    # shape turns each of those from a bespoke integration into a file copy.
    #
    # PERMISSIONS
    # -----------
    # Export needs +:read+, matching the comment endpoints — the people who
    # most need to take feedback out are reviewers who cannot edit the asset.
    #
    # Import also needs only +:read+, because it is a bulk version of posting a
    # comment, which is itself a read-level action. One thing is gated higher:
    # an imported document may *claim* a thread is already resolved, and
    # accepting that claim is a lifecycle decision equivalent to
    # {CommentThreadsController#resolve}, which requires +:modify+. Without
    # that permission everything is imported +open+, so an uploaded file can
    # never silently close outstanding feedback.
    class CommentExportsController < ApplicationController
      include CommentSerialization

      MAX_IMPORT_BYTES = 8.megabytes

      before_action :authenticate_hybrid!
      before_action :require_write_scope!, only: %i[create]
      before_action :set_asset

      # GET /api/v1/assets/:asset_id/comments/export
      #
      # Query params:
      #   format      — "jsonld" (default) or "pdf"
      #   version_id  — only threads discussed on that version
      #   status      — open | addressed | verified | resolved
      #   unresolved  — "true" for only threads still needing action
      #   annotated   — "true" for only threads anchored to the media
      def show
        case params[:export_format].presence || params[:format].presence || "jsonld"
        when "pdf"    then render_pdf
        when "jsonld", "json" then render_jsonld
        else
          render json: { error: "Unsupported export format. Use 'jsonld' or 'pdf'." },
                 status: :unprocessable_entity
        end
      end

      # POST /api/v1/assets/:asset_id/comments/import
      #
      #   { "document": { "@context": "...", "type": "AnnotationPage", "items": [...] },
      #     "source_label": "ziflow" }
      #
      # The document may also be sent as the raw request body with a
      # +application/ld+json+ content type, which is how another W3C-speaking
      # system would naturally hand it over.
      def create
        document = import_document
        return if performed?

        result = Annotations::WebAnnotationImporter.new(
          asset: @asset,
          document: document,
          user: current_user,
          source_label: params[:source_label],
          honour_status: folder_permission?(@asset.folder, :modify),
        ).call

        render json: result.to_h.merge(asset_id: @asset.id), status: :created
      rescue Annotations::WebAnnotationImporter::InvalidDocument => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      private

      def set_asset
        @asset = Asset.active.find_by(id: params[:asset_id]) || Asset.active.find_by!(uuid: params[:asset_id])
        check_asset_read!(@asset)
      end

      def render_jsonld
        document = Annotations::WebAnnotationSerializer.new(
          asset: @asset, threads: exportable_threads, base_url: request.base_url
        ).as_page

        # The registered media type for JSON-LD. A generic application/json
        # would work, but stating it is what lets a consuming system recognise
        # the payload without inspecting it.
        response.headers["Content-Disposition"] =
          %(attachment; filename="#{export_basename}.jsonld")
        render json: document, content_type: "application/ld+json"
      end

      def render_pdf
        pdf = Annotations::ContactSheetPdf.new(
          asset: @asset, threads: exportable_threads
        ).render

        send_data pdf, filename: "#{export_basename}.pdf", type: "application/pdf", disposition: "attachment"
      end

      def export_basename
        base = @asset.title.to_s.parameterize.presence || "asset-#{@asset.id}"
        "#{base}-review"
      end

      # Mirrors {CommentThreadsController#index}'s filters so an export can be
      # narrowed the same way the on-screen list is — exporting only the
      # unresolved notes is the common case for a hand-off.
      def exportable_threads
        # Untriaged machine suggestions are not part of the review and must
        # not appear in an export that may be sent to a client.
        threads = @asset.comment_threads.active.triaged
                        .includes(:created_by, :resolved_by, :origin_version,
                                  comments: [ :author, :asset_version, :annotation_targets ])

        threads = threads.for_version(params[:version_id]) if params[:version_id].present?
        threads = threads.where(status: params[:status])    if params[:status].present?
        threads = threads.unresolved                        if truthy?(params[:unresolved])
        threads = threads.where(id: CommentThread.joins(comments: :annotation_targets).select(:id)) if truthy?(params[:annotated])

        threads.order(created_at: :asc)
      end

      # Accepts the document either wrapped in a +document+ param or as the raw
      # request body, and refuses anything implausibly large before parsing —
      # a multi-megabyte JSON document would otherwise be parsed into memory
      # just to be rejected.
      def import_document
        wrapped = params[:document]
        if wrapped.present?
          return wrapped.respond_to?(:to_unsafe_h) ? wrapped.to_unsafe_h : wrapped
        end

        raw = request.raw_post
        if raw.blank?
          render json: { error: "No annotation document supplied." }, status: :unprocessable_entity
          return nil
        end

        if raw.bytesize > MAX_IMPORT_BYTES
          render json: { error: "Annotation document exceeds #{MAX_IMPORT_BYTES / 1.megabyte}MB." },
                 status: :payload_too_large
          return nil
        end

        JSON.parse(raw)
      rescue JSON::ParserError => e
        render json: { error: "Malformed JSON: #{e.message}" }, status: :unprocessable_entity
        nil
      end

      def truthy?(value)
        ActiveModel::Type::Boolean.new.cast(value).present?
      end
    end
  end
end
