# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Api::V1::CommentExports', type: :request do
  selector_schema = {
    type: :object,
    properties: {
      type: { type: :string, enum: %w[FragmentSelector SvgSelector TextQuoteSelector TextPositionSelector] },
      conformsTo: { type: :string, example: 'http://www.w3.org/TR/media-frags/' },
      value: { type: :string, example: 'xywh=percent:10,20,30,40' },
      'capri:shape': { type: :string, enum: %w[pin rect ellipse arrow line freehand text highlight time] },
      'capri:style': { type: :object, description: 'Stroke colour, width and opacity, lost in plain W3C' },
      'capri:source': { type: :object, description: 'Original media dimensions and rotation' },
    },
  }

  annotation_schema = {
    type: :object,
    properties: {
      id: { type: :string, description: 'Dereferenceable IRI for this annotation' },
      type: { type: :string, example: 'Annotation' },
      motivation: { type: :string, example: 'editing', description: 'W3C Web Annotation motivation vocabulary (§3.3.5)' },
      created: { type: :string, format: 'date-time' },
      creator: { type: :object },
      body: { type: :object, description: 'TextualBody carrying the comment text' },
      target: {
        type: :object,
        properties: {
          source: { type: :string, description: 'IRI of the asset version the note was made against' },
          type: { type: :string, enum: %w[Image Video Text Dataset] },
          selector: selector_schema,
        },
      },
      'capri:commentId': { type: :string, format: :uuid },
      'capri:threadId': { type: :string, format: :uuid },
      'capri:thread': { type: :object, description: 'Thread status and visibility, for a lossless round trip' },
      'capri:versionId': { type: :string, format: :uuid, nullable: true },
    },
  }

  page_schema = {
    type: :object,
    properties: {
      '@context': { type: :array, items: {}, description: 'anno.jsonld plus the capri extension prefix' },
      id: { type: :string },
      type: { type: :string, example: 'AnnotationPage' },
      label: { type: :string },
      'capri:generated': { type: :string, format: 'date-time' },
      'capri:asset': { type: :object },
      items: { type: :array, items: annotation_schema },
    },
  }

  path '/api/v1/assets/{asset_id}/comments/export' do
    get 'Export an asset review as W3C Web Annotations or a PDF sign-off sheet' do
      tags 'Comment Exports'
      produces 'application/ld+json', 'application/pdf'
      security [ Bearer: [] ]
      description <<~DESC
        Emits an asset's review conversation in a form that can leave the DAM.

        **JSON-LD (`export_format=jsonld`)** returns a W3C Web Annotation Data
        Model `AnnotationPage` (https://www.w3.org/TR/annotation-model/), so a
        proofing vendor, archive or approvals system consumes a standard rather
        than a bespoke integration.

        Geometry is always expressed as **percentage media fragments**
        (`xywh=percent:...`), never pixels, so the export is not bound to
        whichever rendition happened to be on screen when the note was drawn.
        Non-rectangular shapes additionally carry an `SvgSelector` in a
        `viewBox="0 0 1 1"` space, and video notes carry a `t=` temporal
        fragment derived from the stored frame number.

        Pure W3C cannot express everything Capri stores: a rectangle and an
        ellipse share a bounding box, and stroke style, exact frame rate,
        drop-frame flag and thread grouping have no standard representation.
        Those travel **alongside** the standard under a namespaced `capri:`
        prefix, which the model explicitly permits — third parties see valid
        W3C and ignore the extension, while Capri reads it back for a lossless
        round trip.

        **PDF (`export_format=pdf`)** renders an annotated contact sheet: the
        version preview with vector-drawn markers over it, numbered badges tied
        to a numbered comment list, statuses and (for video) SMPTE timecode
        headings. Marks are drawn as vectors rather than composited into a
        raster so they stay crisp at print resolution. If the preview cannot be
        read the sheet degrades to a text-only listing rather than failing the
        export.

        Requires only `:read` on the asset folder — the people who most need to
        take feedback out are reviewers who cannot edit the asset.
      DESC

      parameter name: :asset_id, in: :path, type: :string, description: 'Asset UUID or id'
      parameter name: :export_format, in: :query, type: :string, required: false,
                enum: %w[jsonld pdf], description: 'Defaults to jsonld'
      parameter name: :version_id, in: :query, type: :string, required: false,
                description: 'Only threads discussed on this version'
      parameter name: :status, in: :query, type: :string, required: false,
                enum: %w[open addressed verified resolved]
      parameter name: :unresolved, in: :query, type: :boolean, required: false,
                description: 'Only threads still needing action — the common case for a hand-off'
      parameter name: :annotated, in: :query, type: :boolean, required: false,
                description: 'Only threads anchored to a region of the media'

      response '200', 'annotation page or PDF returned' do
        # This operation returns a genuinely different shape per media type: a
        # JSON-LD annotation page, or a PDF byte stream. rswag's `schema` helper
        # copies a single schema across every entry in `produces` (an open TODO
        # in the gem), which would document the PDF as a JSON object. Writing
        # `content` directly is the supported escape hatch: `upgrade_content!`
        # only rewrites the node when a `schema` was set, so this survives.
        metadata[:response][:content] = {
          'application/ld+json' => { schema: page_schema },
          'application/pdf' => {
            schema: { type: :string, format: :binary, description: 'PDF contact sheet (export_format=pdf)' },
          },
        }
        run_test!
      end

      response '401', 'unauthenticated' do
        run_test!
      end

      response '403', 'no read access to the asset folder' do
        run_test!
      end

      response '422', 'unsupported export format' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end

  path '/api/v1/assets/{asset_id}/comments/import' do
    post 'Import a W3C Web Annotation document onto an asset' do
      tags 'Comment Exports'
      consumes 'application/json', 'application/ld+json'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Ingests a W3C `AnnotationPage` (or a bare list of `Annotation`s) as
        Capri threads, comments and annotation targets. Accepts either a
        `document` parameter or the raw request body with an
        `application/ld+json` content type, which is how another W3C-speaking
        system would naturally hand it over. Documents above 8MB are rejected.

        **Attribution is deliberately not honoured.** Trusting the file's
        `creator` would let anyone forge "the Creative Director approved this"
        by editing JSON in a text editor, so the importing user is always
        recorded as the author. The document's claim is preserved as untrusted
        provenance in `import_source.claimed_creator` alongside the original
        IRI and source label.

        **Visibility is always forced to `internal`.** Exposing a thread to
        external guests is a disclosure decision, and an uploaded file must not
        be able to make it.

        **A claimed `resolved` status is only honoured for a caller holding
        `:modify`** on the asset folder, because accepting it is equivalent to
        resolving the thread by hand. Without that permission everything is
        imported `open`, so an upload can never silently close outstanding
        feedback.

        The import is **additive and idempotent**: annotations already present
        are skipped rather than updated, since an import is someone else's copy
        of the past and must not rewrite the live thread. Re-posting the same
        document is therefore a no-op. Replies are nested by resolving targets
        that name another annotation within the same document, and parent
        lookup is scoped to the target asset so importing onto a second asset
        cannot graft comments onto the first.

        Importing requires only `:read`, matching the comment endpoints — it is
        the bulk form of posting a comment.
      DESC

      parameter name: :asset_id, in: :path, type: :string, description: 'Asset UUID or id'
      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: {
          document: {
            type: :object,
            description: 'A W3C AnnotationPage, or an object with an items array',
            properties: {
              '@context': { type: :string, example: 'http://www.w3.org/ns/anno.jsonld' },
              type: { type: :string, example: 'AnnotationPage' },
              items: { type: :array, items: annotation_schema },
            },
          },
          source_label: {
            type: :string,
            example: 'ziflow',
            description: 'Recorded as provenance so imported notes can be traced to their origin',
          },
        },
      }

      response '201', 'document imported' do
        schema type: :object,
               properties: {
                 asset_id: { type: :string, format: :uuid },
                 threads_created: { type: :integer },
                 comments_created: { type: :integer },
                 skipped: { type: :integer, description: 'Annotations already present from a previous import' },
                 errors: { type: :array, items: { type: :string } },
               }
        run_test!
      end

      response '401', 'unauthenticated' do
        run_test!
      end

      response '403', 'no read access to the asset folder' do
        run_test!
      end

      response '413', 'document exceeds the 8MB import limit' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end

      response '422', 'malformed JSON, or not an annotation document' do
        schema type: :object, properties: { error: { type: :string } }
        run_test!
      end
    end
  end
end
