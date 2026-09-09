# frozen_string_literal: true

module Entities
  # Builds entity links from the strings an asset already carries.
  #
  # WHY RESOLUTION RATHER THAN RE-CATALOGUING
  # -----------------------------------------
  # An entity layer that requires someone to revisit every asset is an entity
  # layer that covers the last six months of uploads and nothing else. The
  # existing tags are the accumulated cataloguing effort of the whole library,
  # and they already name most of the entities that matter — just as untyped
  # strings. Resolution reads that effort rather than asking for it again.
  #
  # WHY IT PROPOSES RATHER THAN ASSERTS
  # -----------------------------------
  # Matching a tag to an entity is a guess about identity, and identity is what
  # consent and rights decisions later hang on. Every link created here is
  # unconfirmed, and +AssetEntity.asserted+ excludes it until a person agrees.
  # The alternative — treating a string match as a statement of fact — would
  # mean a spelling coincidence could authorise a release.
  #
  # WHY AMBIGUITY IS NEVER RESOLVED AUTOMATICALLY
  # ---------------------------------------------
  # When one tag matches several entities, that is not a tie to be broken by
  # picking the most-used one. It is the exact failure mode this whole feature
  # exists to fix, and quietly choosing would reintroduce it one layer higher
  # and much harder to see. Ambiguous matches are reported, not linked.
  class Resolver
    # Which relationship a match implies, given the type of the entity matched.
    # The tag itself says nothing about relationship — a tag is just a word —
    # so it has to be inferred from the type, and the inference must be the
    # weakest defensible one.
    #
    # Note what is absent: +shot_by+. A tag naming a person cannot distinguish
    # the photographer from the subject, and guessing wrong here would put a
    # creator credit on an asset because someone appeared in it.
    DEFAULT_RELATIONSHIPS = {
      "person"   => "depicts",
      "product"  => "depicts",
      "brand"    => "depicts",
      "place"    => "located_at",
      "campaign" => "belongs_to",
      "event"    => "belongs_to",
    }.freeze

    Outcome = Struct.new(:linked, :ambiguous, :unmatched, keyword_init: true) do
      def to_h
        {
          linked: linked.map { |l| { tag: l[:tag], entity_id: l[:entity].id, entity_name: l[:entity].name,
                                     entity_type: l[:entity].entity_type, relationship: l[:relationship] } },
          ambiguous: ambiguous.map { |a| { tag: a[:tag], candidates: a[:candidates].map { |c| candidate_hash(c) } } },
          unmatched: unmatched,
        }
      end

      def candidate_hash(entity)
        { id: entity.id, name: entity.name, entity_type: entity.entity_type }
      end
    end

    class << self
      # @param asset [Asset]
      # @param dry_run [Boolean] when true, nothing is written
      # @return [Outcome]
      def call(asset, dry_run: false)
        new(asset, dry_run: dry_run).call
      end
    end

    def initialize(asset, dry_run: false)
      @asset = asset
      @dry_run = dry_run
    end

    # @return [Outcome]
    def call
      linked = []
      ambiguous = []
      unmatched = []

      tags.each do |tag|
        candidates = EntityAlias.candidates_for(tag).to_a

        case candidates.size
        when 0 then unmatched << tag
        when 1
          link = link_for(tag, candidates.first)
          linked << link if link
        else
          ambiguous << { tag: tag, candidates: candidates }
        end
      end

      Outcome.new(linked: linked, ambiguous: ambiguous, unmatched: unmatched)
    end

    private

    attr_reader :asset, :dry_run

    # The tags are read, never written. They remain the raw record of what
    # somebody actually typed, so a resolution pass can be re-run against its
    # own input after the alias table improves — which is the only way anyone
    # will be willing to run it a second time.
    def tags
      Array(asset.properties.to_h["tags"])
        .map { |tag| EntityAlias.normalise(tag) }
        .reject(&:blank?)
        .uniq
    end

    def link_for(tag, entity)
      relationship = DEFAULT_RELATIONSHIPS[entity.entity_type]
      return nil if relationship.nil?

      payload = { tag: tag, entity: entity, relationship: relationship }
      return payload if dry_run

      record = AssetEntity.find_or_initialize_by(
        asset_id: asset.id, entity_id: entity.id, relationship: relationship,
      )

      # An existing link is left exactly as it is. Re-running resolution must
      # never downgrade a confirmed human assertion back to a proposal, which is
      # what a blind upsert would do on the second pass.
      return nil if record.persisted?

      record.source = "tag_resolution"
      record.save!

      payload
    rescue ActiveRecord::RecordInvalid => e
      # A type/relationship mismatch or a race on the unique index is a reason
      # to skip this tag, not to abandon the asset's remaining tags.
      Rails.logger.warn("[EntityResolver] asset=#{asset.id} tag=#{tag}: #{e.message}")
      nil
    end
  end
end
