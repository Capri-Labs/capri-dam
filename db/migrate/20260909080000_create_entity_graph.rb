# Typed entities, and the links between them and assets.
#
# WHY TAGS ARE NOT ENOUGH
# -----------------------
# +assets.properties["tags"]+ is an array of strings, so "Berlin" the city,
# "Berlin" the photographer and "Berlin" the spring campaign are one token. Any
# question that spans them is unaskable: filtering on the tag returns all three
# and there is no way to say which was meant, because the string never carried
# that information in the first place.
#
# The fix is not a better string. It is to make the thing being referred to a
# record — typed, identified, and reusable across every asset that refers to it.
# A tag is a word on a document; an entity is a claim that this asset has a
# stated relationship to a known thing.
#
# WHY THIS IS NOT A TRIPLE STORE
# ------------------------------
# The obvious generalisation is a subject/predicate/object table with free-text
# predicates, and it is a trap. An open predicate vocabulary cannot be indexed
# usefully (every query is a scan over an unbounded string domain), cannot be
# presented in a UI (there is no list to offer), and — decisively — cannot be
# reasoned about for rights or consent, because no policy can enumerate the
# predicates it must consider. A fixed vocabulary of five relationships is
# queryable, offerable and enforceable. It is also revisable: adding a sixth is
# a migration, which is exactly the level of deliberation the decision deserves.
#
# WHY TAGS SURVIVE
# ----------------
# Nothing here deletes or rewrites a tag. Entity links are an additional, typed
# layer resolved *from* the tags, and the tags remain the raw record of what
# somebody actually typed. Destroying them would make the resolution
# irreversible, and a resolution pass that cannot be re-run against its own
# input is a migration nobody will dare repeat.
class CreateEntityGraph < ActiveRecord::Migration[8.1]
  def change
    # A person, product, place, campaign, brand or event.
    create_table :entities, id: :uuid do |t|
      # The type is what disambiguates identical names, so it is part of
      # identity rather than a describing attribute. It is constrained below.
      t.string :entity_type, null: false

      # Display name, as a person would write it.
      t.string :name, null: false

      # The stable, URL-safe handle. Unique *within* a type: "berlin" the place
      # and "berlin" the campaign are different entities and must both be able
      # to hold the obvious slug, or the second one created gets an ugly
      # +berlin-2+ for no reason a user can see.
      t.string :slug, null: false

      t.text :description

      # Type-specific attributes that do not deserve a column on every row —
      # a product's SKU, an event's date, a place's coordinates.
      t.jsonb :properties, null: false, default: {}

      # Identifiers in systems outside this one (Wikidata, a PIM, an internal
      # asset code). Recorded as a map so a later reconciliation pass has
      # something to match on other than the name, which is the least stable
      # identifier an entity has.
      t.jsonb :external_ids, null: false, default: {}

      # MERGE, NOT DELETE
      # -----------------
      # Resolution from free-text tags will create duplicates; that is not a
      # defect, it is what happens when the input is prose. Deleting the loser
      # would orphan every link that already pointed at it — including links a
      # person confirmed by hand. Instead the duplicate is kept and points at
      # its survivor, so old references still resolve and the merge stays
      # legible (and reversible) after the fact.
      t.uuid :canonical_id

      t.references :created_by, null: true, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :entities, [ :entity_type, :slug ], unique: true
    add_index :entities, :canonical_id
    add_index :entities, :name
    # Partial: the overwhelmingly common query is "the entities that are still
    # their own canonical record", and indexing the merged-away duplicates
    # alongside them makes that scan bigger for no reader's benefit.
    add_index :entities, :entity_type, where: "canonical_id IS NULL",
                                       name: "index_entities_on_type_when_canonical"

    add_check_constraint :entities,
                         "entity_type IN ('person', 'product', 'place', 'campaign', 'brand', 'event')",
                         name: "entities_type_in_vocabulary"

    # An entity cannot be its own merge target; that would make the resolution
    # loop in {Entity#canonical} non-terminating.
    add_check_constraint :entities, "canonical_id IS NULL OR canonical_id <> id",
                         name: "entities_canonical_is_not_self"

    add_foreign_key :entities, :entities, column: :canonical_id

    # The other strings that mean this entity.
    #
    # This is the bridge from the existing tag vocabulary. "VW", "Volkswagen"
    # and "volkswagen ag" are one brand, and without somewhere to record that,
    # resolution can only ever match the entity's own name — which would leave
    # the entity layer describing the tidy half of the library and ignoring the
    # half that actually needs it.
    create_table :entity_aliases, id: :uuid do |t|
      t.uuid :entity_id, null: false

      # Stored already normalised (see {EntityAlias.normalise}) so lookup is a
      # plain index probe rather than a function scan over every row.
      t.string :alias_text, null: false

      # Where the alias came from: typed by a person, harvested from an
      # existing tag, or carried in on an import.
      t.string :source, null: false, default: "manual"

      t.timestamps
    end

    add_index :entity_aliases, [ :entity_id, :alias_text ], unique: true
    # NOT unique. An alias matching several entities is the ambiguity this
    # whole feature exists to surface — "berlin" legitimately points at a
    # place, a person and a campaign. A unique index here would force one of
    # them to win arbitrarily at write time, which is precisely the silent
    # collapse that tags already do.
    add_index :entity_aliases, :alias_text
    add_foreign_key :entity_aliases, :entities

    # The link: this asset stands in this relationship to this entity.
    create_table :asset_entities, id: :uuid do |t|
      t.uuid :asset_id,  null: false
      t.uuid :entity_id, null: false

      # From the fixed vocabulary, constrained below. The relationship is what
      # separates the photographer from the person in the frame; without it,
      # both are just "an asset that has something to do with this person" and
      # the ambiguity has merely moved.
      t.string :relationship, null: false

      # How the link came to exist: asserted by a person, resolved from an
      # existing tag, or proposed by a model.
      t.string :source, null: false, default: "manual"

      # Only meaningful for a machine-derived link. Null for a human assertion:
      # a person does not have a confidence score, and defaulting them to 1.0
      # would make the two indistinguishable in exactly the query that needs to
      # tell them apart.
      t.float :confidence

      # CONFIRMATION IS THE POINT
      # -------------------------
      # A resolved or model-proposed link is a guess about identity, and
      # identity is what later phases gate consent and rights on. An unconfirmed
      # link must therefore never be able to masquerade as an assertion. Null
      # here means "nobody has agreed with this yet", and every consumer that
      # matters is expected to say so.
      t.datetime :confirmed_at
      t.references :confirmed_by, null: true, foreign_key: { to_table: :users }
      t.references :created_by,   null: true, foreign_key: { to_table: :users }

      t.timestamps
    end

    # The same asset may relate to the same entity twice under *different*
    # relationships — a photographer who is also in the shot — so the
    # relationship is part of the key rather than a duplicate to be prevented.
    add_index :asset_entities, [ :asset_id, :entity_id, :relationship ],
              unique: true, name: "index_asset_entities_on_asset_entity_relationship"
    add_index :asset_entities, [ :entity_id, :relationship ]
    add_index :asset_entities, :asset_id
    # Powers the review queue: everything a machine proposed that no human has
    # looked at yet. Partial, because once the backlog is worked down this index
    # should be nearly empty — which is the state we want it to be cheap in.
    add_index :asset_entities, :created_at, where: "confirmed_at IS NULL",
                                            name: "index_asset_entities_unconfirmed"

    add_check_constraint :asset_entities,
                         "relationship IN ('depicts', 'shot_by', 'belongs_to', 'located_at', 'mentions')",
                         name: "asset_entities_relationship_in_vocabulary"

    add_check_constraint :asset_entities,
                         "source IN ('manual', 'tag_resolution', 'ai')",
                         name: "asset_entities_source_in_vocabulary"

    # A confidence outside 0..1 is a unit error in the caller, and letting it
    # land makes every threshold comparison downstream quietly wrong.
    add_check_constraint :asset_entities,
                         "confidence IS NULL OR (confidence >= 0 AND confidence <= 1)",
                         name: "asset_entities_confidence_in_range"

    add_foreign_key :asset_entities, :assets
    add_foreign_key :asset_entities, :entities
  end
end
