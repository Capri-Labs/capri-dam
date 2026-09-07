# Presentation settings for a distribution portal, normalised and made safe to
# render.
#
# WHY THIS IS NOT JUST A HASH READ
# --------------------------------
# The branding blob reaches the page in two places that are injection sinks:
# +logo_url+ becomes an +img src+, and +accent+ is interpolated into inline
# CSS. Neither is attacker-controlled in the usual sense — an internal user
# sets them — but "only staff can set it" is exactly the assumption that makes
# a stored-XSS bug survive review, and a compromised or careless internal
# account should not be able to hand every external partner a hostile page.
#
# So both are whitelisted rather than escaped: +accent+ must match a literal
# hex colour, and +logo_url+ must be http(s) or a site-relative path. Anything
# else falls back to the default instead of being sanitised into something
# nearly-right, because a half-cleaned URL is how filters get bypassed.
module Portal
  class Branding
    DEFAULT_ACCENT = "#2563eb".freeze
    # Three- or six-digit hex, nothing else. Deliberately excludes rgb(),
    # var() and named colours: the set of CSS values that can smuggle a
    # payload is not one worth enumerating.
    ACCENT_PATTERN = /\A#(?:\h{3}|\h{6})\z/
    HEADLINE_LIMIT = 120
    MESSAGE_LIMIT  = 2000

    # @param raw [Hash, nil] the +review_links.branding+ blob
    def initialize(raw)
      # jsonb can legitimately hold a non-object; never assume a Hash.
      @raw = raw.is_a?(Hash) ? raw.stringify_keys : {}
    end

    # @return [String] a hex colour safe to interpolate into CSS
    def accent
      candidate = @raw["accent"].to_s.strip
      ACCENT_PATTERN.match?(candidate) ? candidate.downcase : DEFAULT_ACCENT
    end

    # @return [String, nil] the portal heading, or nil to fall back to the link name
    def headline
      @raw["headline"].to_s.strip.presence&.truncate(HEADLINE_LIMIT)
    end

    # @return [String, nil] an introductory message shown above the grid
    def message
      @raw["message"].to_s.strip.presence&.truncate(MESSAGE_LIMIT)
    end

    # @return [String, nil] a URL safe to place in an img src
    def logo_url
      candidate = @raw["logo_url"].to_s.strip
      return nil if candidate.blank?
      # A protocol-relative URL ("//evil.example") inherits the page scheme and
      # is not site-relative, so it is rejected with the rest.
      return candidate if candidate.start_with?("/") && !candidate.start_with?("//")

      uri = URI.parse(candidate)
      %w[http https].include?(uri.scheme&.downcase) ? candidate : nil
    rescue URI::InvalidURIError
      nil
    end

    # @return [Hash] the normalised, render-safe view of the blob
    def to_h
      { "accent" => accent, "headline" => headline, "message" => message, "logo_url" => logo_url }
    end

    # Normalises input on the way *in*, so the database holds only keys the
    # portal understands and an operator editing the row later sees exactly
    # what will be rendered.
    #
    # @param params [ActionController::Parameters, Hash, nil]
    # @return [Hash]
    def self.sanitise(params)
      raw = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params
      new(raw.is_a?(Hash) ? raw : {}).to_h.compact
    end
  end
end
