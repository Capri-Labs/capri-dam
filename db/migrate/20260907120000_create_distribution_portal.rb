# Turns the review-link machinery into a second surface: a branded
# **distribution portal** with per-asset permissions and download tracking.
#
# WHY THIS EXTENDS review_links RATHER THAN ADDING A PARALLEL MODEL
# ----------------------------------------------------------------
# A portal link needs exactly what {CreateReviewLinks} already built and
# argued for: revocation (a forwarded link must have a kill switch), identity
# (who took the file), and metering (how often it was opened). Standing those
# up a second time would mean two copies of a digest-only bearer token, two
# bcrypt passphrase paths and two expiry ceilings — and the next fix to any of
# them would land in one copy only. The two surfaces differ in what a guest may
# *do*, not in how the credential works, so the credential is shared and the
# behaviour is switched on +kind+.
#
# WHY GRANTS ARE A TABLE AND NOT A FLAG
# -------------------------------------
# +review_links.allow_downloads+ is link-wide: every asset behind the link is
# downloadable or none is. A distribution portal exists precisely because that
# is too coarse — a partner may take the retouched crops but not the raw
# masters sitting in the same collection. Permission therefore has to be
# per-asset, which needs a row per asset.
class CreateDistributionPortal < ActiveRecord::Migration[8.1]
  def change
    # Existing rows are review links and must keep behaving exactly as before,
    # so the default preserves today's semantics rather than opting anything in.
    add_column :review_links, :kind, :string, null: false, default: "review"

    # Portal chrome: title, accent colour, logo url, welcome message. JSONB
    # because it is presentation that will grow, and a column per adjustment
    # would mean a migration every time someone wants a different heading.
    # Never consulted for an access decision.
    add_column :review_links, :branding, :jsonb, null: false, default: {}

    add_index :review_links, :kind

    add_check_constraint :review_links,
                         "kind IN ('review', 'portal')",
                         name: "review_links_kind_valid"

    # Which assets a portal exposes, and what may be done with each.
    #
    # Absence of a row means *not shared*. Default-deny is the only safe
    # reading for a distribution surface: an asset added to the collection
    # tomorrow must not silently appear in a portal handed out today.
    create_table :portal_grants, id: :uuid do |t|
      t.references :review_link, null: false, foreign_key: true, type: :uuid
      # assets.id is uuid.
      t.uuid :asset_id, null: false

      # "view"     — may see it in the portal and open a preview.
      # "download" — may also take the file.
      # Viewing is the floor; there is no grant that permits download without
      # sight, because you cannot choose a file you cannot see.
      t.string :permission, null: false, default: "view"

      t.timestamps
    end

    add_foreign_key :portal_grants, :assets, column: :asset_id
    add_index :portal_grants, :asset_id
    # One grant per asset per link: two rows would make the effective
    # permission depend on row order.
    add_index :portal_grants, [ :review_link_id, :asset_id ], unique: true

    add_check_constraint :portal_grants,
                         "permission IN ('view', 'download')",
                         name: "portal_grants_permission_valid"

    # One row per file a guest actually took.
    #
    # WHY NOT asset_usage_events
    # --------------------------
    # That table's +user_id+ is +bigint NOT NULL+ and a {ReviewGuest} is
    # deliberately not a {User} — it has no account, no credentials and no
    # permission surface. Pointing one at the other would either require
    # minting real accounts for outsiders or writing a null into a non-null
    # column. Internal usage stats and external distribution are also asked
    # different questions ("what do our staff use" vs "what left the building,
    # to whom"), so they stay separate.
    create_table :portal_downloads, id: :uuid do |t|
      t.references :review_link, null: false, foreign_key: true, type: :uuid
      # Null when the link never asked who the guest was. The download is still
      # recorded — "someone holding this link took this file" is the fact that
      # matters, and dropping it because the name is unknown would leave the
      # least-identified links with the emptiest audit trail.
      t.references :review_guest, null: true, foreign_key: true, type: :uuid
      t.uuid :asset_id, null: false

      # Kept for incident response: "which address pulled the masters at 3am"
      # is the first question asked after a leak.
      t.string :ip_address
      t.string :user_agent

      t.datetime :created_at, null: false
    end

    add_foreign_key :portal_downloads, :assets, column: :asset_id
    add_index :portal_downloads, :asset_id
    add_index :portal_downloads, [ :review_link_id, :created_at ]
  end
end
