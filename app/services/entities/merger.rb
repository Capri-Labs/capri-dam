# frozen_string_literal: true

module Entities
  # Folds a duplicate entity into the record that survives.
  #
  # WHY MERGE IS A FIRST-CLASS OPERATION
  # ------------------------------------
  # Duplicates are not a defect in resolution; they are what happens when the
  # input is prose. "VW", "Volkswagen" and "Volkswagen AG" will be created as
  # three brands by three different people before anyone notices. If the only
  # remedy is deletion, the cost of cleaning up is losing every link that
  # pointed at the loser — including ones a person confirmed by hand — so
  # nobody cleans up and the graph rots into the same ambiguity it replaced.
  #
  # So the duplicate is kept and made to point at its survivor. Old references
  # still resolve, the merge stays legible after the fact, and undoing it is a
  # matter of clearing one column.
  class Merger
    Result = Struct.new(:canonical, :duplicate, :links_moved, :links_discarded, :aliases_moved,
                        keyword_init: true)

    class << self
      # @param duplicate [Entity] the record being folded away
      # @param canonical [Entity] the record that survives
      # @return [Result]
      # @raise [ArgumentError] on a merge that would corrupt the graph
      def call(duplicate:, canonical:)
        new(duplicate: duplicate, canonical: canonical).call
      end
    end

    def initialize(duplicate:, canonical:)
      @duplicate = duplicate
      @canonical = canonical
    end

    # @return [Result]
    def call
      validate!

      moved = 0
      discarded = 0
      aliases_moved = 0

      Entity.transaction do
        duplicate.asset_entities.find_each do |link|
          if move_link(link)
            moved += 1
          else
            discarded += 1
          end
        end

        aliases_moved = move_aliases

        # The duplicate's own name has to become an alias of the survivor, or
        # the merge destroys the very string that caused someone to create the
        # duplicate in the first place — and the next resolution pass recreates
        # it.
        aliases_moved += 1 if adopt_name_as_alias

        duplicate.update!(canonical_id: canonical.id)
      end

      Result.new(canonical: canonical, duplicate: duplicate, links_moved: moved,
                 links_discarded: discarded, aliases_moved: aliases_moved)
    end

    private

    attr_reader :duplicate, :canonical

    def validate!
      raise ArgumentError, "An entity cannot be merged into itself" if duplicate.id == canonical.id

      # Merging across types would silently reclassify every asset linked to the
      # duplicate — turning "located at Berlin" into "belongs to Berlin" — and
      # the relationship matrix would reject half the links on the way through,
      # leaving the merge half-applied.
      if duplicate.entity_type != canonical.entity_type
        raise ArgumentError, "Cannot merge a #{duplicate.entity_type} into a #{canonical.entity_type}"
      end

      raise ArgumentError, "The surviving entity is itself merged away" if canonical.merged?
    end

    # @return [Boolean] true when the link was moved, false when it was a dupe
    def move_link(link)
      existing = AssetEntity.find_by(
        asset_id: link.asset_id, entity_id: canonical.id, relationship: link.relationship,
      )

      if existing
        # Both records described the same claim. Keep whichever carries human
        # agreement, so a merge can never demote a confirmed link back to a
        # proposal just because the duplicate happened to be processed second.
        promote(existing, link) if link.asserted? && !existing.asserted?
        link.destroy!
        false
      else
        link.update_columns(entity_id: canonical.id, updated_at: Time.current)
        true
      end
    end

    def promote(existing, link)
      existing.update!(
        source: link.source,
        confidence: link.confidence,
        confirmed_at: link.confirmed_at,
        confirmed_by_id: link.confirmed_by_id,
      )
    end

    def move_aliases
      moved = 0

      duplicate.entity_aliases.find_each do |entity_alias|
        next if EntityAlias.exists?(entity_id: canonical.id, alias_text: entity_alias.alias_text)

        entity_alias.update_columns(entity_id: canonical.id, updated_at: Time.current)
        moved += 1
      end

      moved
    end

    def adopt_name_as_alias
      normalised = EntityAlias.normalise(duplicate.name)
      return false if normalised == EntityAlias.normalise(canonical.name)
      return false if EntityAlias.exists?(entity_id: canonical.id, alias_text: normalised)

      EntityAlias.create!(entity: canonical, alias_text: normalised, source: "manual")
      true
    end
  end
end
