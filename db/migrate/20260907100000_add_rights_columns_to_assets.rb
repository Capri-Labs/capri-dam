class AddRightsColumnsToAssets < ActiveRecord::Migration[8.1]
  # Legacy free-text spellings, mapped to the canonical vocabulary. This
  # duplicates Rights::UsageTerms::SYNONYMS on purpose: a migration records what
  # happened to the data on the day it ran, and must keep producing that result
  # even after the application's vocabulary grows or is renamed.
  BACKFILL_SYNONYMS = {
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

  CODES = BACKFILL_SYNONYMS.values.uniq.freeze

  # Identity entries for the codes themselves, so a legacy value that already
  # used the canonical spelling is not downgraded to the default by being
  # absent from the synonym table.
  LOOKUP = CODES.index_with { |code| code }.merge(BACKFILL_SYNONYMS).freeze

  def up
    # Typed columns for the two rights facts the platform actually enforces on.
    # They previously lived as free text inside assets.properties, where nothing
    # constrained them: usage terms were compared against one exact English
    # literal (so every other spelling read as "not internal", i.e. as
    # permission to distribute), and expiry dates were handed to Time.zone.parse
    # or cast in SQL, both of which raise on input like "2024".
    #
    # NOT NULL with a default on usage_terms because the safe state must be the
    # one you get by doing nothing: an asset whose rights nobody recorded is
    # internal, not free to distribute. license_expires_at stays nullable —
    # "no expiry" is a legitimate, common state and is distinct from "unknown".
    add_column :assets, :usage_terms, :string, null: false, default: "internal_only"
    add_column :assets, :license_expires_at, :datetime

    add_index :assets, :usage_terms

    # Partial: most assets have no expiry, and the only queries that touch this
    # column are looking for the ones that do (expiry forecasts, enforcement).
    add_index :assets,
              :license_expires_at,
              where: "license_expires_at IS NOT NULL",
              name: "index_assets_on_license_expires_at_present"

    backfill!

    # Only enforced after the backfill, so the constraint cannot fail on data
    # that predates the vocabulary.
    execute <<~SQL.squish
      ALTER TABLE assets
        ADD CONSTRAINT assets_usage_terms_in_vocabulary
        CHECK (usage_terms IN (#{CODES.map { |c| "'#{c}'" }.join(", ")}))
    SQL
  end

  def down
    execute "ALTER TABLE assets DROP CONSTRAINT IF EXISTS assets_usage_terms_in_vocabulary"
    remove_index :assets, name: "index_assets_on_license_expires_at_present"
    remove_index :assets, :usage_terms
    remove_column :assets, :license_expires_at
    remove_column :assets, :usage_terms
  end

  private

  # Copies the legacy JSONB values into the new columns and rewrites the JSONB
  # to match, so there is exactly one spelling of the truth afterwards.
  #
  # Anything that cannot be understood is not discarded and not guessed at: the
  # original text is moved to a +_raw+ key for a human to correct, the column
  # falls back to the restrictive default, and the count is reported in the
  # migration log. Silently coercing an unreadable rights statement into a
  # permissive one is the failure mode this whole migration exists to remove.
  def backfill!
    unrecognised_terms = 0
    malformed_dates    = 0
    scanned            = 0

    # A throwaway class rather than ::Asset. A migration must keep behaving the
    # same after the model above it changes; binding to the live model would let
    # a future default scope, validation or callback silently alter what this
    # historical rewrite does.
    assets = Class.new(ActiveRecord::Base) { self.table_name = "assets" }

    say_with_time "Backfilling rights columns from assets.properties" do
      assets.select(:id, :properties).find_in_batches(batch_size: 500) do |batch|
        batch.each do |asset|
          props = asset.properties || {}

          raw_terms = props["usage_terms"]
          key       = raw_terms.to_s.downcase.strip.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
          terms     = LOOKUP[key]

          if terms.nil?
            terms = "internal_only"
            if raw_terms.present?
              unrecognised_terms += 1
              props["usage_terms_raw"] = raw_terms
            end
          end

          raw_expiry = props["license_expires_at"]
          expiry     = parse_expiry(raw_expiry)

          if expiry.nil? && raw_expiry.present?
            malformed_dates += 1
            props["license_expires_at_raw"] = raw_expiry
          end

          props["usage_terms"]        = terms
          props["license_expires_at"] = expiry&.iso8601

          # update_all, not save: this is a data rewrite, not a user edit.
          # Going through the model would fire the embedding broadcast and
          # smart-collection routing once per asset, and bump updated_at across
          # the whole table.
          assets.where(id: asset.id).update_all(
            usage_terms:        terms,
            license_expires_at: expiry,
            # The Hash, not its JSON encoding: passing a String to a jsonb
            # column stores it as a JSON *scalar string*, so every subsequent
            # read returns "{\"usage_terms\":...}" instead of a hash.
            properties:         props
          )

          scanned += 1
        end
      end

      "#{scanned} assets; #{unrecognised_terms} unrecognised usage terms and " \
        "#{malformed_dates} malformed expiry dates preserved under *_raw keys"
    end
  end

  def parse_expiry(value)
    return nil if value.blank?

    text = value.to_s.strip
    if text.match?(/\A\d{4}-\d{2}-\d{2}\z/)
      Date.iso8601(text).in_time_zone.end_of_day
    else
      Time.iso8601(text).in_time_zone
    end
  rescue ArgumentError, RangeError, TypeError
    nil
  end
end
