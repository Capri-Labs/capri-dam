module Rights
  # Strict parsing for +assets.license_expires_at+.
  #
  # The column this feeds replaced a free-text JSONB key that readers passed
  # straight to +Time.zone.parse+. That was unsafe in three separate ways, each
  # demonstrable:
  #
  # * +Time.zone.parse("2024")+ *raises* +ArgumentError+, so a single asset with
  #   a year-only value aborted {Collection#compliance_violations} for the whole
  #   collection — and in {Reports::AnalyticsService} the equivalent SQL cast was
  #   wrapped in +rescue 0+, so one malformed row reported "no licences expiring"
  #   precisely when the data was worst.
  # * +Time.zone.parse("12345")+ returns the year *12*, turning a typo into an
  #   asset that has been expired for two millennia.
  # * +Time.zone.parse("2026-02-30")+ silently returns 2 March, inventing a date
  #   nobody wrote.
  #
  # So this parser accepts ISO 8601 and nothing else. Locale-dependent forms
  # like +"31/12/2026"+ are rejected rather than guessed at, because +"01/02/2026"+
  # is a different day in London and New York and a rights expiry is not a field
  # to be wrong about by ten months. Rejected input is preserved verbatim
  # (see {Asset#normalise_rights}) so a human can correct it; it is never
  # coerced into a date.
  module LicenseExpiry
    module_function

    # @param value [String, Time, Date, DateTime, nil]
    # @return [ActiveSupport::TimeWithZone, nil] +nil+ when absent or malformed
    #
    # A bare +YYYY-MM-DD+ is read as the *end* of that day: a licence stated to
    # expire on 31 December is good through 31 December, and reading it as
    # midnight would retire the asset a day early, every time.
    def parse(value)
      case value
      when nil            then nil
      when Time, DateTime then value.in_time_zone
      when Date           then value.in_time_zone.end_of_day
      when String         then parse_string(value)
      else                     nil
      end
    end

    # Whether a value was supplied but could not be understood — the state that
    # deserves a validation error rather than a silent +nil+, since "no expiry
    # recorded" and "an expiry we failed to read" have opposite risk profiles.
    #
    # @param value [Object]
    # @return [Boolean]
    def malformed?(value)
      return false if value.nil?
      return false if value.is_a?(String) && value.strip.empty?

      parse(value).nil?
    end

    # Serialises back to the canonical string form used in +properties+.
    #
    # @param value [Time, nil]
    # @return [String, nil]
    def serialise(value)
      value&.iso8601
    end

    # @api private
    def parse_string(value)
      text = value.strip
      return nil if text.empty?

      if text.match?(/\A\d{4}-\d{2}-\d{2}\z/)
        # Date.iso8601 rejects 2026-02-30 instead of rolling it into March.
        Date.iso8601(text).in_time_zone.end_of_day
      else
        Time.iso8601(text).in_time_zone
      end
    rescue ArgumentError, RangeError, TypeError
      nil
    end
  end
end
