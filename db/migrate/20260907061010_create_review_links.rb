# Signed, revocable review links that let an external client comment on an
# asset or collection without a Capri account.
#
# WHY A TABLE, WHEN COLLECTION SHARE LINKS NEED NONE
# --------------------------------------------------
# {Collection#generate_share_token} uses Rails' +signed_id+: an HMAC-signed,
# self-describing token with no database row. That is a good fit for read-only
# browsing, but it cannot support review, for three reasons:
#
# 1. *It cannot be revoked.* A signed id is valid until it expires. If a client
#    forwards a review link to a competitor there is no kill switch short of
#    rotating the application's secret. Read-only exposure of a curated
#    collection is a tolerable risk; a link that lets an outsider *write* into
#    your review threads is not.
# 2. *It carries no identity.* Guest comments have to be attributable — "the
#    client said this" is the entire point of the feature — and a signed id
#    knows only which record it was minted for.
# 3. *It cannot be scoped or metered.* Whether a guest may download, whether
#    they must identify themselves, and how often the link has been opened are
#    all per-link facts with nowhere to live.
class CreateReviewLinks < ActiveRecord::Migration[8.1]
  def change
    create_table :review_links, id: :uuid do |t|
      t.string :name, null: false

      # Only the digest is stored. The raw token is shown once, at creation,
      # and is unrecoverable afterwards — so a dump of this table cannot be
      # used to walk into anyone's review. SHA-256 rather than bcrypt is
      # correct here: the token is 32 random bytes, not a human-chosen
      # password, so there is no dictionary to slow an attacker down and a
      # deliberately slow digest would only cost latency on every request.
      t.string :token_digest, null: false

      # Exactly one of these is set; enforced by a check constraint below.
      # assets.id is uuid, collections.id is bigint.
      t.uuid   :asset_id
      t.bigint :collection_id

      t.references :created_by, null: false, foreign_key: { to_table: :users }

      # Always required. An external grant with no end date is a permanent
      # hole in the perimeter that nobody remembers to close.
      t.datetime :expires_at, null: false
      t.datetime :revoked_at

      t.boolean :allow_comments,  null: false, default: true
      # Off by default: viewing an asset to comment on it does not imply the
      # right to keep a copy of the master file.
      t.boolean :allow_downloads, null: false, default: false
      # Anonymous feedback is rarely actionable, so a guest is asked who they
      # are before commenting. It is an identity prompt, not authentication.
      t.boolean :require_email,   null: false, default: true

      # Optional second factor for genuinely sensitive material, shared out of
      # band. bcrypt here because this one *is* human-chosen and low entropy.
      t.string :passphrase_digest

      t.integer  :access_count, null: false, default: 0
      t.datetime :last_accessed_at

      t.timestamps
    end

    add_index :review_links, :token_digest, unique: true
    add_index :review_links, :asset_id
    add_index :review_links, :collection_id
    add_index :review_links, :expires_at

    add_foreign_key :review_links, :assets, column: :asset_id
    add_foreign_key :review_links, :collections, column: :collection_id

    # A link that points at nothing, or at two things, has no defined scope.
    add_check_constraint :review_links,
                         "(asset_id IS NOT NULL AND collection_id IS NULL) OR " \
                         "(asset_id IS NULL AND collection_id IS NOT NULL)",
                         name: "review_links_exactly_one_target"

    # A named person on the far side of a link. Created on first identification
    # rather than up front, because the sender rarely knows who will actually
    # open the link.
    create_table :review_guests, id: :uuid do |t|
      t.references :review_link, null: false, foreign_key: true, type: :uuid
      t.string :email, null: false
      t.string :name
      t.datetime :last_seen_at

      t.timestamps
    end

    # One identity per email per link, so a guest returning tomorrow resumes as
    # themselves instead of forking a second persona.
    add_index :review_guests, [ :review_link_id, :email ], unique: true
  end
end
