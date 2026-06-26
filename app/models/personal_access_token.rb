# Personal Access Token (PAT) — a long-lived, user-scoped bearer token used
# by CLI tools and external API scripts to authenticate against the DAM API
# without sharing the user's password.
#
# == Security model
#
# * The raw token is generated once and returned to the user **exactly once**
#   at creation time.  It is never persisted in plaintext.
# * A SHA-256 digest is stored in +token_digest+.  Incoming tokens are
#   hashed and compared against this digest.
# * +last_four+ stores the final 4 characters of the raw token so that users
#   can visually identify a token in the UI without any security exposure.
# * +active: false+ immediately revokes a token without deleting it (audit
#   trail preserved).
#
# == Token format
#
#   dat_<32 random hex chars>
#   ↑ prefix marks it as a DAM Access Token
#
# @example Create and return the raw token once
#   pat, raw = PersonalAccessToken.generate_for(user, name: "CI/CD pipeline")
#   # => pat is the persisted record; raw is the one-time plaintext
#
# @example Authenticate an incoming request
#   PersonalAccessToken.authenticate("dat_abc123...")
#   # => User | nil
class PersonalAccessToken < ApplicationRecord
  belongs_to :user

  VALID_SCOPES = %w[read write admin].freeze
  PREFIX       = "dat_"

  validates :name,         presence: true, length: { maximum: 100 }
  validates :token_digest, presence: true, uniqueness: true
  validates :last_four,    presence: true, length: { is: 4 }
  validates :scopes,       inclusion: { in: VALID_SCOPES }

  scope :active,   -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
  scope :unexpired, -> {
    where("expires_at IS NULL OR expires_at > ?", Time.current)
  }

  # ---------------------------------------------------------------------------
  # Class methods
  # ---------------------------------------------------------------------------

  # Generates a new raw token and persists its digest.
  #
  # @param user [User]
  # @param name [String] human-readable label (e.g. "CI/CD pipeline")
  # @param scopes [String] comma-separated scope list; defaults to "read"
  # @param expires_at [Time, nil]
  # @return [Array(PersonalAccessToken, String)] [record, raw_token]
  def self.generate_for(user, name:, scopes: "read", expires_at: nil)
    raw    = "#{PREFIX}#{SecureRandom.hex(16)}"
    digest = Digest::SHA256.hexdigest(raw)

    pat = create!(
      user:         user,
      name:         name,
      token_digest: digest,
      last_four:    raw.last(4),
      scopes:       scopes,
      expires_at:   expires_at,
      active:       true,
    )

    [ pat, raw ]
  end

  # Looks up a PAT from a raw token string.
  #
  # Touches +last_used_at+ on a hit so admins can audit stale tokens.
  #
  # @param raw_token [String]
  # @return [User, nil]
  def self.authenticate(raw_token)
    return nil unless raw_token&.start_with?(PREFIX)

    digest = Digest::SHA256.hexdigest(raw_token)
    pat    = active.unexpired.find_by(token_digest: digest)
    return nil unless pat

    pat.touch(:last_used_at)
    pat.user
  end

  # ---------------------------------------------------------------------------
  # Instance methods
  # ---------------------------------------------------------------------------

  def expired?
    expires_at.present? && expires_at < Time.current
  end

  def revoke!
    update!(active: false)
  end
end
