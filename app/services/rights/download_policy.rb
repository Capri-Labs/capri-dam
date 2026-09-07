module Rights
  # The single question every byte-delivery path must ask before handing over an
  # asset: *may this audience receive this file, right now?*
  #
  # == Why one object
  #
  # Nine files in this application call +send_data+, +send_file+ or
  # +rails_blob_path+, and one concern mints signed storage URLs that bypass
  # controllers entirely. A rights check written per controller is a rights check
  # that will be missing from the tenth surface somebody adds, and the surfaces
  # that matter most — the guest review path, the share portal — are exactly the
  # ones a contributor is least likely to remember. So the decision lives here,
  # every caller funnels through it, and the specs enumerate the surfaces.
  #
  # == What is being enforced
  #
  # Two independent facts can each block delivery, and they block *different
  # audiences*:
  #
  # * *Usage terms* answer "may this leave the organisation". An +internal_only+
  #   asset is perfectly fine for staff to open; what it must never do is reach
  #   a guest, a review link or a distribution portal.
  # * *Licence expiry* answers "are we still allowed to use this at all". A
  #   lapsed licence is a problem for everyone, so it blocks *export* for
  #   internal users too.
  #
  # == Viewing is not distribution
  #
  # Internally, this policy gates download and export — not the viewer. Blocking
  # inline delivery for staff would blank every thumbnail in the application the
  # day a licence lapsed, which is how a safety control gets switched off. The
  # asset stays visible to the people who need to see that it has a problem; what
  # stops is their ability to take a copy of it.
  #
  # Externally there is no such distinction: showing an internal-only asset to a
  # guest *is* the disclosure, so both preview and download are refused.
  class DownloadPolicy
    # +:internal+ — an authenticated member of the organisation.
    # +:external+ — a guest, review-link holder or portal visitor. Anyone
    # outside the organisation, regardless of how they were let in.
    AUDIENCES = %i[internal external].freeze

    # +:view+     — inline display; only meaningful for the internal audience,
    #               where it is always permitted.
    # +:download+ — the bytes leave, as a file the recipient keeps.
    PURPOSES = %i[view download].freeze

    # A decision, not a boolean: the caller almost always needs to tell the user
    # *why*, and "you may not download this" without a reason produces a support
    # ticket rather than a corrected licence.
    Decision = Struct.new(:allowed, :code, :message, keyword_init: true) do
      def allowed? = allowed
      def denied?  = !allowed
    end

    ALLOWED = Decision.new(allowed: true, code: :ok, message: nil).freeze

    # @param asset [Asset]
    # @param audience [Symbol] one of {AUDIENCES}
    # @param purpose [Symbol] one of {PURPOSES}
    # @param user [User, nil] the internal user, when there is one
    # @param at [Time] the moment to judge expiry against
    def initialize(asset, audience:, purpose: :download, user: nil, at: Time.current)
      raise ArgumentError, "unknown audience #{audience.inspect}" unless AUDIENCES.include?(audience)
      raise ArgumentError, "unknown purpose #{purpose.inspect}"   unless PURPOSES.include?(purpose)

      @asset    = asset
      @audience = audience
      @purpose  = purpose
      @user     = user
      @at       = at
    end

    class << self
      # @return [Decision]
      def for(asset, **kwargs)
        new(asset, **kwargs).decision
      end

      # @return [Boolean]
      def allow?(asset, **kwargs)
        self.for(asset, **kwargs).allowed?
      end

      # Splits a set of assets into those that may be delivered and those that
      # may not, keeping each refusal's reason attached.
      #
      # This is what bulk export needs. A ZIP that silently omits three files is
      # worse than one that refuses to build: the recipient has no way to know
      # anything is missing, and will assume the archive is complete.
      #
      # @return [Array(Array<Asset>, Array<Hash>)] permitted assets, and
      #   +{asset:, code:, message:}+ for each refusal
      def partition(assets, **kwargs)
        permitted = []
        refused   = []

        assets.each do |asset|
          decision = self.for(asset, **kwargs)

          if decision.allowed?
            permitted << asset
          else
            refused << { asset: asset, code: decision.code, message: decision.message }
          end
        end

        [ permitted, refused ]
      end
    end

    # @return [Decision]
    def decision
      @decision ||= evaluate
    end

    private

    attr_reader :asset, :audience, :purpose, :user, :at

    def evaluate
      return ALLOWED if asset.nil?

      audience == :external ? external_decision : internal_decision
    end

    # A guest is outside the organisation, so both conditions apply and both
    # apply to viewing as well as downloading.
    def external_decision
      unless Rights::UsageTerms.externally_distributable?(asset.usage_terms)
        return deny(
          :not_externally_distributable,
          "This asset is restricted to '#{asset.usage_terms_label}' and cannot be shared outside the organisation."
        )
      end

      return expired_denial if asset.license_expired?(at)

      ALLOWED
    end

    def internal_decision
      # Staff may always look at their own organisation's assets, including ones
      # with a problem — seeing that an asset is unusable is the first step to
      # fixing it.
      return ALLOWED if purpose == :view

      # An administrator has to be able to retrieve an expired asset: somebody
      # must be able to archive it, hand it to legal, or replace it. The bypass
      # is deliberately limited to the *internal* audience — an admin creating a
      # guest link is not the admin receiving the file.
      return ALLOWED if administrator?

      return expired_denial if asset.license_expired?(at)

      ALLOWED
    end

    def expired_denial
      deny(
        :license_expired,
        "This asset's licence expired on #{asset.license_expires_at.to_date.iso8601} and it can no longer be distributed."
      )
    end

    def deny(code, message)
      Decision.new(allowed: false, code: code, message: message)
    end

    def administrator?
      return false if user.nil?

      (user.respond_to?(:admin?) && user.admin?) ||
        (user.respond_to?(:super_admin?) && user.super_admin?)
    end
  end
end
