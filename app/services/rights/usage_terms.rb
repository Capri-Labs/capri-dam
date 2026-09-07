module Rights
  # The controlled vocabulary for +assets.usage_terms+.
  #
  # Before this module, usage terms were an unconstrained free-text string in
  # +assets.properties+ that defaulted to +"Internal Use Only"+. Nothing stopped
  # an importer, an API client or a bulk edit from writing +"internal use"+,
  # +"Internal-Only"+ or +"see contract"+, and {Collection#compliance_violations}
  # decided whether an asset could be exposed externally by comparing that
  # string to one exact literal. Every spelling that missed the literal read as
  # "not internal", i.e. as permission to distribute. A vocabulary that decides
  # what may leave the organisation cannot be open-ended.
  #
  # Terms describe *distribution rights*, not copyright statements: the question
  # every downstream check asks is "may this leave the building, and until
  # when?".
  module UsageTerms
    # Each term carries the one fact enforcement needs — whether the asset may
    # be distributed outside the organisation at all. Expiry is orthogonal and
    # lives in its own column: a licence window can close on any term.
    TERMS = {
      "internal_only" => {
        label:    "Internal Use Only",
        external: false,
      },
      "editorial_only" => {
        label:    "Editorial Use Only",
        external: true,
      },
      "rights_managed" => {
        label:    "Rights Managed",
        external: true,
      },
      "royalty_free" => {
        label:    "Royalty Free",
        external: true,
      },
      "public_domain" => {
        label:    "Public Domain",
        external: true,
      },
    }.freeze

    CODES = TERMS.keys.freeze

    # The most restrictive term, and therefore both the default for a new asset
    # and the landing place for anything unrecognised.
    DEFAULT = "internal_only"

    # Spellings seen in the wild — legacy free-text values, XMP fields, and the
    # abbreviations importers use. Keys are already normalised (downcased, with
    # runs of non-alphanumerics collapsed to a single underscore), so
    # +"Royalty-Free"+, +"royalty free"+ and +"ROYALTY_FREE"+ all arrive here as
    # +"royalty_free"+ and only genuinely different words need listing.
    SYNONYMS = {
      "internal"            => "internal_only",
      "internal_use"        => "internal_only",
      "internal_use_only"   => "internal_only",
      "internal_only"       => "internal_only",
      "confidential"        => "internal_only",
      "restricted"          => "internal_only",
      "do_not_distribute"   => "internal_only",
      "all_rights_reserved" => "internal_only",

      "editorial"           => "editorial_only",
      "editorial_use"       => "editorial_only",
      "editorial_use_only"  => "editorial_only",
      "news_only"           => "editorial_only",

      "licensed"            => "rights_managed",
      "rights_managed"      => "rights_managed",
      "rm"                  => "rights_managed",
      "managed_rights"      => "rights_managed",
      "limited_license"     => "rights_managed",

      "royalty_free"        => "royalty_free",
      "rf"                  => "royalty_free",
      "unlimited_use"       => "royalty_free",

      "public_domain"       => "public_domain",
      "pd"                  => "public_domain",
      "cc0"                 => "public_domain",
      "no_rights_reserved"  => "public_domain",
    }.freeze

    module_function

    # Every canonical code maps to itself, so a code can never be silently
    # downgraded by being absent from the synonym table — a bug the specs
    # caught: +editorial_only+ was a valid code with no matching synonym, so an
    # API client sending the exact code got +internal_only+ back.
    LOOKUP = CODES.index_with { |code| code }.merge(SYNONYMS).freeze

    # Maps an arbitrary input to a canonical code.
    #
    # Anything unrecognised becomes {DEFAULT} rather than being passed through.
    # This is deliberately fail-closed: an unreadable rights statement is not
    # evidence of permission, and the alternative — treating "we could not parse
    # this" as "no restriction recorded" — turns a data-quality problem into a
    # distribution incident. Callers that need to know whether the input was
    # actually understood should ask {recognised?} and preserve the original
    # text themselves.
    #
    # @param value [String, Symbol, nil]
    # @return [String] one of {CODES}
    def normalise(value)
      LOOKUP.fetch(canonical_key(value), DEFAULT)
    end

    # Whether the input mapped to a term by being understood, rather than by
    # falling back to {DEFAULT}.
    #
    # @param value [String, Symbol, nil]
    # @return [Boolean]
    def recognised?(value)
      LOOKUP.key?(canonical_key(value))
    end

    # @param code [String]
    # @return [Boolean] whether assets on this term may be distributed outside
    #   the organisation at all
    def externally_distributable?(code)
      TERMS.dig(code.to_s, :external) || false
    end

    # The English display label, for logs, exports and compliance messages.
    # A translated label belongs with the rights management UI (Phase 10b),
    # which will key its own i18n bundle on the codes in {CODES}.
    #
    # @param code [String]
    # @return [String]
    def label(code)
      TERMS.dig(code.to_s, :label) || TERMS.dig(DEFAULT, :label)
    end

    # @api private
    # Reduces an input to the shape {SYNONYMS} is keyed on, so that casing,
    # hyphens, spaces and stray punctuation are not five different terms.
    def canonical_key(value)
      value.to_s.downcase.strip.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
    end
  end
end
