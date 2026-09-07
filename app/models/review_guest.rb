# A named external person on the far side of a {ReviewLink}.
#
# NOT A USER, DELIBERATELY
# ------------------------
# It would have been less code to create a real {User} for each guest, but a
# User is an *account*: it can be granted folder policies, added to groups,
# counted against a seat licence and, if the password reset flow is ever
# reachable, signed into. A guest should be able to leave feedback and nothing
# else, so they get a record that has no credentials to compromise and no
# permission surface to widen.
#
# IDENTITY HERE IS ATTRIBUTION, NOT AUTHENTICATION
# ------------------------------------------------
# The email is self-asserted and unverified — anyone holding the link could
# type any address. That is understood and accepted: the *link* is the
# credential, and the email exists so feedback reads as "Priya at the client"
# rather than "Anonymous". Nothing is authorised on the strength of it, and it
# is never matched against a {User} record, because silently adopting a
# colleague's identity because the addresses happen to match would be a
# privilege escalation dressed up as a convenience.
class ReviewGuest < ApplicationRecord
  # Reserved TLD (RFC 2606): guaranteed never to resolve, so a placeholder
  # address can never be mailed by accident.
  ANONYMOUS_DOMAIN = "@guests.invalid".freeze

  belongs_to :review_link
  has_many :comments, dependent: :nullify
  has_many :created_threads, class_name: "CommentThread", foreign_key: :created_by_guest_id, dependent: :nullify,
           inverse_of: :created_by_guest

  validates :email, presence: true,
                    format: { with: URI::MailTo::EMAIL_REGEXP, message: "must be a valid email address" }
  validates :name, length: { maximum: 120 }, allow_blank: true
  validates :email, uniqueness: { scope: :review_link_id }

  before_validation :normalise_email

  # Finds or creates the guest identity for this link, so someone returning
  # tomorrow resumes as themselves rather than forking a second persona.
  #
  # @param review_link [ReviewLink]
  # @param email [String]
  # @param name [String, nil]
  # @return [ReviewGuest]
  def self.identify!(review_link:, email:, name: nil)
    normalised = email.to_s.strip.downcase
    # Nobody may claim the reserved anonymous domain; otherwise a guest could
    # type someone else's placeholder address and inherit their comments.
    if normalised.end_with?(ANONYMOUS_DOMAIN)
      raise ActiveRecord::RecordInvalid, new(review_link: review_link).tap { |g|
        g.errors.add(:email, "must be a valid email address")
      }
    end

    guest = find_or_initialize_by(review_link_id: review_link.id, email: normalised)
    guest.name = name if name.present?
    guest.last_seen_at = Time.current
    guest.save!
    guest
  end

  # An identity for a reviewer on a link that does not ask who they are.
  #
  # The address uses the reserved +.invalid+ TLD (RFC 2606) so it can never be
  # routed: this is a placeholder to satisfy the unique index and give the
  # person a stable handle for the session, not a contact address, and nothing
  # should ever try to mail it.
  #
  # @param review_link [ReviewLink]
  # @return [ReviewGuest]
  def self.anonymous!(review_link:)
    create!(review_link: review_link,
            email: "anon-#{SecureRandom.hex(8)}#{ANONYMOUS_DOMAIN}",
            last_seen_at: Time.current)
  end

  # @return [Boolean] whether this guest never told us who they are
  def anonymous?
    email.to_s.end_with?(ANONYMOUS_DOMAIN)
  end

  # @return [String]
  def display_name
    return name.presence || "Guest reviewer" if anonymous?

    name.presence || email
  end

  def touch_seen!
    update_columns(last_seen_at: Time.current, updated_at: Time.current)
  end

  private

  def normalise_email
    self.email = email.to_s.strip.downcase.presence
  end
end
