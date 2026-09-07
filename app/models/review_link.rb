# A revocable, time-boxed invitation for someone without a Capri account to
# review an asset or a collection.
#
# THE TOKEN IS A BEARER CREDENTIAL
# --------------------------------
# Whoever holds the token is the reviewer. That makes it exactly as sensitive
# as a password, and it is treated that way: only {#token_digest} is persisted,
# the raw value is returned once from {.mint} and is unrecoverable afterwards.
# A leaked database dump therefore yields no usable links.
#
# SHA-256, NOT BCRYPT
# -------------------
# The token is 32 bytes from {SecureRandom}, so there is no dictionary for an
# attacker to work through and nothing for a deliberately slow hash to defend
# against. Bcrypt here would only add latency to every single guest request.
# The optional {#passphrase}, by contrast, *is* human-chosen and low entropy,
# so that one does use bcrypt.
class ReviewLink < ApplicationRecord
  # Devise pulls bcrypt in, but the constant is not guaranteed to be loaded by
  # the time this model is autoloaded, so require it explicitly.
  require "bcrypt"

  # 32 bytes, url-safe. Long enough that guessing is not a threat model.
  TOKEN_BYTES = 32
  DEFAULT_EXPIRY = 30.days
  # Nothing may outlive this, however it was requested. An external grant is a
  # hole in the perimeter, and the one thing that reliably closes it is time.
  MAX_EXPIRY = 180.days

  belongs_to :asset, optional: true
  belongs_to :collection, optional: true
  belongs_to :created_by, class_name: "User"

  has_many :review_guests, dependent: :destroy
  has_many :comment_threads, dependent: :nullify

  validates :name, presence: true
  validates :token_digest, presence: true, uniqueness: true
  validates :expires_at, presence: true
  validate  :exactly_one_target
  validate  :expiry_within_bounds

  scope :live, -> { where(revoked_at: nil).where("expires_at > ?", Time.current) }

  class << self
    # Creates a link and returns it alongside the *only* copy of its raw token.
    #
    # @return [Array(ReviewLink, String)] the record and the raw token
    def mint(target: nil, **attributes)
      token = SecureRandom.urlsafe_base64(TOKEN_BYTES)
      link = new(attributes.merge(token_digest: digest(token)))
      link.target = target if target
      link.expires_at ||= DEFAULT_EXPIRY.from_now
      link.save!
      [ link, token ]
    end

    # Resolves a raw token to its link, or nil.
    #
    # Looks up by digest so the raw token is never compared in the database and
    # never appears in a query log.
    #
    # @param token [String]
    # @return [ReviewLink, nil]
    def find_by_token(token)
      return nil if token.blank?

      find_by(token_digest: digest(token))
    end

    # @param token [String]
    # @return [String]
    def digest(token)
      Digest::SHA256.hexdigest(token.to_s)
    end
  end

  # @return [Boolean] whether this link may still be used at all
  def usable?
    revoked_at.nil? && expires_at.present? && expires_at.future?
  end

  # Why the link is unusable, for a guest-facing message. Distinguishing
  # expired from revoked is genuinely useful — "ask for a fresh link" and
  # "this was withdrawn" are different conversations — and neither discloses
  # anything an attacker could not learn by waiting.
  #
  # @return [Symbol, nil]
  def unusable_reason
    return :revoked if revoked_at.present?
    return :expired if expires_at.blank? || expires_at.past?

    nil
  end

  # @return [Boolean]
  def revoked?
    revoked_at.present?
  end

  # Immediate kill switch. This is the capability that ruled out +signed_id+
  # for review links in the first place.
  def revoke!(at: Time.current)
    update!(revoked_at: at)
  end

  # @return [Boolean] whether a passphrase must be supplied before entry
  def passphrase_required?
    passphrase_digest.present?
  end

  # Sets or clears the optional passphrase.
  #
  # @param raw [String, nil]
  def passphrase=(raw)
    self.passphrase_digest = raw.presence && BCrypt::Password.create(raw)
  end

  # @param raw [String, nil]
  # @return [Boolean]
  def passphrase_matches?(raw)
    return true unless passphrase_required?
    return false if raw.blank?

    BCrypt::Password.new(passphrase_digest) == raw
  rescue BCrypt::Errors::InvalidHash
    false
  end

  # Every asset this link grants sight of.
  #
  # Resolved through the *live* collection membership rather than snapshotted
  # at mint time, so removing an asset from a collection withdraws it from
  # every outstanding review link at once. The alternative — a frozen list —
  # would mean a retracted asset stayed visible to external reviewers.
  #
  # @return [ActiveRecord::Relation<Asset>]
  def scoped_assets
    return Asset.active.where(id: asset_id) if asset_id.present?

    collection ? collection.assets.merge(Asset.active) : Asset.none
  end

  # @param candidate [Asset, String, nil]
  # @return [Boolean]
  def covers?(candidate)
    id = candidate.respond_to?(:id) ? candidate.id : candidate
    return false if id.blank?

    scoped_assets.exists?(id: id)
  end

  # @return [Asset, Collection, nil]
  def target
    asset || collection
  end

  # Assigns the single thing this link grants access to, clearing the other
  # target so the "exactly one" invariant cannot be broken by reassignment.
  #
  # @param record [Asset, Collection]
  # @raise [ArgumentError] for anything else
  def target=(record)
    case record
    when Asset      then self.asset = record; self.collection = nil
    when Collection then self.collection = record; self.asset = nil
    else raise ArgumentError, "A review link must target an Asset or a Collection, got #{record.class}"
    end
  end

  # @return [String]
  def target_label
    asset&.title || collection&.name || "Review"
  end

  # Records that the link was opened. Uses a bare UPDATE rather than a
  # validated save because this fires on every guest page view and must not be
  # able to fail the request it is measuring.
  def record_access!
    update_columns(
      access_count: access_count + 1,
      last_accessed_at: Time.current,
      updated_at: Time.current,
    )
  end

  private

  def exactly_one_target
    return if asset_id.present? ^ collection_id.present?

    errors.add(:base, "A review link must target exactly one asset or collection")
  end

  def expiry_within_bounds
    return if expires_at.blank?
    return if expires_at <= MAX_EXPIRY.from_now + 1.minute

    errors.add(:expires_at, "cannot be more than #{MAX_EXPIRY.inspect} away")
  end
end
