# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Api::V1::Portals', type: :request do
  grant_schema = {
    type: :object,
    properties: {
      asset_id: { type: :string, format: :uuid },
      permission: {
        type: :string,
        enum: %w[view download],
        description: 'What the recipient may do. `view` allows preview only.',
      },
    },
    required: %w[asset_id],
  }

  portal_asset_schema = {
    type: :object,
    properties: {
      id: { type: :string, format: :uuid },
      title: { type: :string },
      usage_terms: { type: :string, example: 'external_ok' },
      license_expires_at: { type: :string, format: 'date-time', nullable: true },
      permission: { type: :string, enum: %w[view download], nullable: true },
      granted: { type: :boolean, description: 'False means the asset is in the collection but not shared' },
      externally_distributable: {
        type: :boolean,
        description: <<~DESC,
          Whether rights will actually let this asset leave. A grant on an asset
          where this is `false` is recorded but never honoured — surfaced here so
          the gap is visible while configuring, rather than discovered by the
          recipient.
        DESC
      },
    },
  }

  portal_schema = {
    type: :object,
    properties: {
      id: { type: :string, format: :uuid },
      name: { type: :string, example: 'Autumn campaign — agency drop' },
      kind: { type: :string, enum: %w[portal] },
      status: { type: :string, enum: %w[active expired revoked] },
      collection_id: { type: :integer, nullable: true },
      asset_id: { type: :string, format: :uuid, nullable: true },
      target_label: { type: :string },
      branding: {
        type: :object,
        description: 'Sanitised on write; see the POST description.',
        properties: {
          accent: { type: :string, example: '#1f6feb' },
          logo_url: { type: :string, nullable: true },
          headline: { type: :string, nullable: true },
          message: { type: :string, nullable: true },
        },
      },
      expires_at: { type: :string, format: 'date-time' },
      revoked_at: { type: :string, format: 'date-time', nullable: true },
      require_email: { type: :boolean },
      passphrase_required: { type: :boolean },
      access_count: { type: :integer },
      last_accessed_at: { type: :string, format: 'date-time', nullable: true },
      granted_count: { type: :integer, description: 'Assets the sender has picked' },
      downloadable_count: { type: :integer, description: 'Of those, how many are granted `download`' },
      distributable_count: {
        type: :integer,
        description: 'Of those, how many rights will actually release. May be lower than granted_count.',
      },
      download_count: { type: :integer, description: 'Files actually taken through this portal' },
      created_at: { type: :string, format: 'date-time' },
      created_by: { type: :string, nullable: true },
      assets: {
        type: :array,
        items: portal_asset_schema,
        description: 'Present on show/create/update only. Every asset in the target, granted or not.',
      },
    },
  }

  write_payload = {
    type: :object,
    properties: {
      name: { type: :string, example: 'Autumn campaign — agency drop' },
      collection_id: { type: :integer, nullable: true },
      asset_id: { type: :string, format: :uuid, nullable: true },
      expires_at: {
        type: :string,
        format: 'date-time',
        description: "Defaults to 30 days; capped at #{ReviewLink::MAX_EXPIRY.inspect}",
      },
      require_email: { type: :boolean, default: false },
      passphrase: { type: :string, nullable: true, description: 'Write-only. Stored as a bcrypt digest.' },
      branding: {
        type: :object,
        properties: {
          accent: { type: :string, description: 'Hex colour. Anything else is replaced with the default.' },
          logo_url: { type: :string, description: 'http(s) or site-relative only.' },
          headline: { type: :string },
          message: { type: :string },
        },
      },
      grants: { type: :array, items: grant_schema },
    },
  }

  path '/api/v1/portals' do
    get 'List distribution portals' do
      tags 'Distribution Portals'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Lists branded distribution portals, newest first.

        Scoped to portals the caller created unless they are an administrator,
        for the same reason review links are: what a colleague has sent outside
        the organisation is not general-purpose internal information.

        Portals and review links share a table but never share a list — a token
        minted for one surface is rejected by the other.

        The token is never present here. Only its SHA-256 digest is stored, and
        that digest is not exposed either, so a compromised session cannot be
        used to harvest working portal URLs.
      DESC

      parameter name: :status, in: :query, required: false, schema: { type: :string, enum: %w[active expired revoked] }

      response '200', 'portals listed' do
        schema type: :object,
               properties: {
                 portals: { type: :array, items: portal_schema },
                 meta: { type: :object, properties: { total: { type: :integer } } },
               }
        run_test!
      end

      response '401', 'unauthenticated' do
        run_test!
      end
    end

    post 'Mint a distribution portal' do
      tags 'Distribution Portals'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Creates a branded, revocable, time-boxed portal through which people
        without a Capri account can browse and download selected material.

        **The `token` and `url` in this response are the only copies that will
        ever exist.** Only a digest is stored, so a lost token cannot be
        recovered — revoke and mint a new one instead.

        Supply exactly one of `collection_id` or `asset_id`. Requires `:modify`
        on the target: being allowed to view a collection is not the same as
        being allowed to hand it to a partner.

        **Three independent gates decide what a recipient sees.** An asset must
        still be in the collection, *and* carry an explicit grant, *and* pass
        the rights policy. Absence of a grant is a denial, so a portal shared
        last month cannot silently start offering this month's work.

        A grant records only that the sender is willing; it cannot widen rights.
        Granting `download` on an internal-only asset is recorded but never
        honoured, and the response's `distributable_count` reports the gap.

        `branding` is whitelisted rather than escaped, because it reaches an
        `img` source and an inline stylesheet: `accent` must be a hex colour and
        `logo_url` must be http(s) or site-relative. Values that fail are
        dropped, not rejected — a bad colour should not lose you the portal.
      DESC

      parameter name: :payload, in: :body, required: true, schema: write_payload

      response '201', 'portal minted' do
        schema portal_schema.deep_merge(
          properties: {
            token: { type: :string, description: 'Shown exactly once. Not recoverable.' },
            url: { type: :string, example: 'https://dam.example.com/s/portal/<token>' },
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

      response '422', 'no target, or an expiry beyond the cap' do
        run_test!
      end
    end
  end

  path '/api/v1/portals/{id}' do
    parameter name: :id, in: :path, required: true, schema: { type: :string, format: :uuid }

    get 'Show a portal and its full pick list' do
      tags 'Distribution Portals'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Returns the portal plus **every** asset in its target — granted or not —
        so an editor can render the whole pick list rather than only what is
        already shared, and can see which picks rights will not release.

        Returns 404 rather than 403 for another user's portal: whether a
        particular portal exists is itself information about what a colleague
        has shared externally.
      DESC

      response '200', 'portal found' do
        schema portal_schema
        run_test!
      end

      response '404', 'not found, or belongs to another user' do
        run_test!
      end
    end

    patch 'Update a portal' do
      tags 'Distribution Portals'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Changes settings, branding, expiry, passphrase or grants. **The target
        cannot be changed** — re-pointing a live portal at a different
        collection would hand an outsider material they were never shown while
        the URL already in their inbox looks unchanged.

        `grants` is **declarative**: the set you send replaces the set that
        exists, and anything omitted is withdrawn. An incremental "add these"
        API makes removal something you have to remember to do separately, and
        the permission you forget to remove is the one that leaks.

        Grants are confined to the portal's own target; an asset from elsewhere
        is ignored rather than honoured. An unrecognised permission falls back
        to `view`, the weakest, so a typo cannot widen access.
      DESC

      parameter name: :payload, in: :body, required: true, schema: write_payload

      response '200', 'portal updated' do
        schema portal_schema
        run_test!
      end

      response '404', 'not found, or belongs to another user' do
        run_test!
      end

      response '422', 'validation failed' do
        run_test!
      end
    end

    delete 'Revoke a portal' do
      tags 'Distribution Portals'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        Revokes immediately; the token stops working on the next request.

        The row is **not** deleted. The download records collected through it
        point here for their provenance — "who was sent what, and under which
        grant" is exactly what an audit asks later — so only the credential's
        usefulness ends.
      DESC

      response '200', 'portal revoked' do
        schema portal_schema
        run_test!
      end

      response '404', 'not found, or belongs to another user' do
        run_test!
      end
    end
  end

  path '/api/v1/portals/{id}/downloads' do
    parameter name: :id, in: :path, required: true, schema: { type: :string, format: :uuid }

    get 'The distribution record for a portal' do
      tags 'Distribution Portals'
      produces 'application/json'
      security [ Bearer: [] ]
      description <<~DESC
        What actually left through this portal, and to whom — newest first,
        capped at 500 entries.

        Only successful deliveries are recorded: a refused or failed request is
        not a distribution and must not appear in a record used to answer "did
        we send them that file?".

        `guest_email` is null for a recipient who was never asked to identify
        themselves, rather than showing the reserved internal anonymous address.
      DESC

      response '200', 'download record returned' do
        schema type: :object,
               properties: {
                 downloads: {
                   type: :array,
                   items: {
                     type: :object,
                     properties: {
                       id: { type: :string, format: :uuid },
                       asset_id: { type: :string, format: :uuid },
                       asset_title: { type: :string, nullable: true },
                       guest: { type: :string, nullable: true, example: 'Priya' },
                       guest_email: { type: :string, nullable: true },
                       ip_address: { type: :string, nullable: true },
                       downloaded_at: { type: :string, format: 'date-time' },
                     },
                   },
                 },
                 meta: { type: :object, properties: { total: { type: :integer } } },
               }
        run_test!
      end

      response '404', 'not found, or belongs to another user' do
        run_test!
      end
    end
  end
end
