# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Api::V1::ReviewLinks', type: :request do
  guest_schema = {
    type: :object,
    properties: {
      id: { type: :string, format: :uuid },
      email: {
        type: :string,
        nullable: true,
        description: 'Null for a reviewer who was never asked to identify themselves',
      },
      name: { type: :string, nullable: true },
      display_name: { type: :string, example: 'Priya' },
      anonymous: { type: :boolean },
      last_seen_at: { type: :string, format: 'date-time', nullable: true },
      comment_count: { type: :integer },
    },
  }

  review_link_schema = {
    type: :object,
    properties: {
      id: { type: :string, format: :uuid },
      name: { type: :string, example: 'Autumn campaign — client review' },
      target_type: { type: :string, enum: %w[asset collection] },
      target_id: { type: :string, description: 'Asset UUID or collection id' },
      target_label: { type: :string, example: 'Hero shot' },
      asset_count: { type: :integer, description: 'Assets currently in scope; follows live collection membership' },
      expires_at: { type: :string, format: 'date-time' },
      revoked_at: { type: :string, format: 'date-time', nullable: true },
      status: { type: :string, enum: %w[active expired revoked] },
      allow_comments: { type: :boolean },
      allow_downloads: { type: :boolean },
      require_email: { type: :boolean },
      passphrase_protected: { type: :boolean },
      access_count: { type: :integer },
      last_accessed_at: { type: :string, format: 'date-time', nullable: true },
      guest_count: { type: :integer },
      comment_count: { type: :integer },
      created_by: { type: :object, nullable: true },
      created_at: { type: :string, format: 'date-time' },
    },
  }

  write_payload = {
    type: :object,
    properties: {
      name: { type: :string, example: 'Autumn campaign — client review' },
      asset_id: { type: :string, format: :uuid, nullable: true },
      collection_id: { type: :integer, nullable: true },
      expires_at: {
        type: :string,
        format: 'date-time',
        description: "Defaults to 30 days; capped at #{ReviewLink::MAX_EXPIRY.inspect}",
      },
      allow_comments: { type: :boolean, default: true },
      allow_downloads: { type: :boolean, default: false },
      require_email: { type: :boolean, default: true },
      passphrase: {
        type: :string,
        nullable: true,
        description: 'Optional second factor, shared out of band. Stored as a bcrypt digest and never returned.',
      },
    },
  }

  path '/api/v1/review_links' do
    get 'List review links' do
      tags 'Review Links'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Lists external review links, newest first.

        Scoped to links the caller created, unless they are an administrator: a
        user should not be able to enumerate what their colleagues have shared
        outside the organisation.

        The token is never present here. Only its SHA-256 digest is stored, and
        even that is not exposed — so a compromised session cannot be used to
        harvest working review URLs for links it did not create.
      DESC

      parameter name: :status, in: :query, required: false, schema: { type: :string, enum: %w[active expired revoked] }
      parameter name: :asset_id, in: :query, required: false, schema: { type: :string, format: :uuid }
      parameter name: :collection_id, in: :query, required: false, schema: { type: :integer }

      response '200', 'review links listed' do
        schema type: :object,
               properties: {
                 review_links: { type: :array, items: review_link_schema },
                 meta: { type: :object, properties: { total: { type: :integer } } },
               }
        run_test!
      end

      response '401', 'unauthenticated' do
        run_test!
      end
    end

    post 'Mint a review link' do
      tags 'Review Links'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Creates a revocable, time-boxed link that lets someone without a Capri
        account view and comment on an asset or a collection.

        **The `token` and `url` in this response are the only copies that will
        ever exist.** Only a digest is stored, so a lost token cannot be
        recovered — revoke and mint a new one instead. This is deliberate: it
        means a dump of the database does not hand an attacker a set of live
        review URLs.

        Supply exactly one of `asset_id` or `collection_id`. A collection link
        resolves through *live* membership, so removing an asset from the
        collection withdraws it from every outstanding link at once.

        Requires `:modify` on the target, not the `:read` that ordinary
        commenting needs — being allowed to discuss an asset internally is not
        the same as being allowed to send it outside the organisation.

        `expires_at` is always set: it defaults to 30 days and is hard-capped,
        because an external grant with no end date is a permanent hole in the
        perimeter that nobody remembers to close.
      DESC

      parameter name: :review_link, in: :body, required: true, schema: write_payload

      response '201', 'review link minted' do
        schema review_link_schema.deep_merge(
          properties: {
            token: { type: :string, description: 'Shown exactly once. Not recoverable.' },
            url: { type: :string, example: 'https://dam.example.com/s/reviews/<token>' },
          },
        )
        run_test!
      end

      response '403', 'no modify permission on the target' do
        run_test!
      end

      response '404', 'target not found' do
        run_test!
      end

      response '422', 'no target, two targets, or an expiry beyond the cap' do
        run_test!
      end
    end
  end

  path '/api/v1/review_links/{id}' do
    parameter name: :id, in: :path, required: true, schema: { type: :string, format: :uuid }

    get 'Show a review link and who has used it' do
      tags 'Review Links'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Returns the link plus the guests who have identified themselves through
        it and how much each has said — the "who did we actually show this to"
        record that an audit asks for later.

        Returns 404 rather than 403 for another user's link: whether a
        particular link exists is itself information about what a colleague has
        shared externally.
      DESC

      response '200', 'review link found' do
        schema review_link_schema.deep_merge(
          properties: { guests: { type: :array, items: guest_schema } },
        )
        run_test!
      end

      response '404', 'not found, or not the caller’s link' do
        run_test!
      end
    end

    patch 'Update a review link' do
      tags 'Review Links'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Adjusts settings, expiry or passphrase on a live link.

        **The target cannot be changed.** Re-pointing an existing link at a
        different asset would silently grant an outsider access to material they
        were never shown, while the URL already sitting in their inbox looks
        unchanged. Mint a new link instead.

        Send `passphrase: ""` to remove passphrase protection.
      DESC

      parameter name: :review_link, in: :body, required: true, schema: write_payload

      response '200', 'review link updated' do
        schema review_link_schema
        run_test!
      end

      response '404', 'not found, or not the caller’s link' do
        run_test!
      end

      response '422', 'validation failed' do
        run_test!
      end
    end

    delete 'Revoke a review link' do
      tags 'Review Links'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Ends the link's usefulness as a credential, immediately and for
        everyone holding it.

        This **revokes rather than deletes**. Comments already collected through
        the link point at this record for their provenance, so the row survives
        and only its ability to admit anyone stops. The response shows the link
        with `status: "revoked"`.

        Revocation is effective for asset bytes too: guest previews and
        downloads are proxied through the application rather than handed out as
        signed storage URLs, precisely so that revoking actually revokes.
      DESC

      response '200', 'review link revoked' do
        schema review_link_schema
        run_test!
      end

      response '404', 'not found, or not the caller’s link' do
        run_test!
      end
    end
  end
end
