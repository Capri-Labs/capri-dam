# frozen_string_literal: true

module Search
  # The allow-list of fields a query AST may reference, and the single source of
  # truth for what the graphical query builder is allowed to offer.
  #
  # Why an explicit registry rather than reflecting over the schema:
  #
  # 1. *Reach.* `assets.properties` is a `jsonb` blob holding both curated
  #    metadata and implementation detail — `checksum_sha256`, `storage_path`,
  #    `thumbnail_data`. Reflection cannot tell those apart, so an AST compiled
  #    from reflection could read any of them. The registry inverts the default:
  #    a field is unreachable until it is listed.
  #
  # 2. *Types.* A JSON value has no type. `(properties->>'file_size')::bigint`
  #    is only safe because we decided that key holds an integer; Postgres will
  #    raise on a row where it does not. The registry is where that decision is
  #    recorded, and it is what lets the compiler choose a cast and an operator
  #    set rather than guessing from whatever the caller happened to send.
  #
  # 3. *One list, not two.* `GET /api/v1/search/fields` serves this registry to
  #    the builder UI, so the pick-list a user sees and the allow-list the
  #    compiler enforces cannot drift. A hardcoded client list would eventually
  #    offer a field the server rejects, and the failure would look like a bug
  #    in the query rather than a stale constant.
  module FieldRegistry
    Field = Struct.new(:name, :label, :type, :source, :path, :values, :group, keyword_init: true) do
      def to_h
        {
          name: name,
          label: label || name.humanize,
          type: type.to_s,
          group: group.to_s,
          operators: FieldRegistry.operators_for(type),
          values: values,
        }.compact
      end
    end

    # `present`/`blank` are available on every type because "was this filled in
    # at all" is a different question from any comparison — and on a jsonb
    # source it is the only way to ask about a key that may simply be absent.
    COMMON_OPERATORS = %w[present blank].freeze

    OPERATORS = {
      string:   %w[eq not_eq contains not_contains starts_with ends_with in not_in] + COMMON_OPERATORS,
      text:     %w[contains not_contains eq not_eq] + COMMON_OPERATORS,
      enum:     %w[eq not_eq in not_in] + COMMON_OPERATORS,
      number:   %w[eq not_eq gt gte lt lte between] + COMMON_OPERATORS,
      datetime: %w[before after between eq] + COMMON_OPERATORS,
      boolean:  %w[eq] + COMMON_OPERATORS,
      # A tag list is a set, so equality is the wrong question to ask of it.
      # "Does it contain" is the useful one, and it splits three ways.
      array:    %w[has_any has_all none_of] + COMMON_OPERATORS,
    }.freeze

    # Schema field types, as authored in MetadataSchema tabs, mapped onto the
    # types the compiler understands. Anything unrecognised falls back to
    # :string, which is the most permissive *operator* set but still a typed,
    # allow-listed path — never a raw passthrough.
    SCHEMA_TYPE_MAP = {
      "number" => :number, "date" => :datetime, "datetime" => :datetime,
      "boolean" => :boolean, "tag" => :array, "textarea" => :text
    }.freeze

    def self.operators_for(type)
      OPERATORS.fetch(type.to_sym, COMMON_OPERATORS)
    end

    # rubocop:disable Layout/LineLength
    def self.definitions
      @definitions ||= [
        # --- Real columns ----------------------------------------------------
        Field.new(name: "title",              type: :string,   source: :column,   path: "title",              group: :core),
        Field.new(name: "status",             type: :enum,     source: :column,   path: "status",             group: :core, values: Asset.statuses.keys),
        Field.new(name: "created_at",         type: :datetime, source: :column,   path: "created_at",         group: :core),
        Field.new(name: "updated_at",         type: :datetime, source: :column,   path: "updated_at",         group: :core),
        Field.new(name: "published_at",       type: :datetime, source: :column,   path: "published_at",       group: :core),
        Field.new(name: "folder_id",          type: :string,   source: :column,   path: "folder_id",          group: :core),
        Field.new(name: "license_expires_at", type: :datetime, source: :column,   path: "license_expires_at", group: :rights),
        Field.new(name: "usage_terms",        type: :string,   source: :column,   path: "usage_terms",        group: :rights),

        # --- Curated `properties` keys ---------------------------------------
        Field.new(name: "content_type",        type: :string, source: :property, path: "content_type",        group: :file),
        Field.new(name: "file_size",           type: :number, source: :property, path: "file_size",           group: :file),
        Field.new(name: "original_filename",   type: :string, source: :property, path: "original_filename",   group: :file),
        Field.new(name: "description",         type: :text,   source: :property, path: "description",         group: :descriptive),
        Field.new(name: "alt_text",            type: :text,   source: :property, path: "alt_text",            group: :descriptive),
        Field.new(name: "tags",                type: :array,  source: :property, path: "tags",                group: :descriptive),
        Field.new(name: "width",               type: :number, source: :property, path: "width",               group: :image),
        Field.new(name: "height",              type: :number, source: :property, path: "height",              group: :image),
        Field.new(name: "color_mode",          type: :string, source: :property, path: "color_mode",          group: :image),
        Field.new(name: "video_width",         type: :number, source: :property, path: "video_width",         group: :video),
        Field.new(name: "video_height",        type: :number, source: :property, path: "video_height",        group: :video),
        Field.new(name: "video_bitrate",       type: :number, source: :property, path: "video_bitrate",       group: :video),
        Field.new(name: "video_codec",         type: :string, source: :property, path: "video_codec",         group: :video),
        Field.new(name: "video_format",        type: :string, source: :property, path: "video_format",        group: :video),
        Field.new(name: "audio_codec",         type: :string, source: :property, path: "audio_codec",         group: :audio),
        Field.new(name: "audio_bitrate",       type: :number, source: :property, path: "audio_bitrate",       group: :audio),
        Field.new(name: "applied_schema_name", type: :string, source: :property, path: "applied_schema_name", group: :schema),
      ].freeze
    end
    # rubocop:enable Layout/LineLength

    def self.by_name
      @by_name ||= definitions.index_by(&:name).freeze
    end

    # Schema-defined metadata fields are *data*, not code, so they cannot live in
    # the frozen list above. They are still allow-listed: only a key that a
    # MetadataSchema actually declares via `map_to_property` becomes reachable,
    # which keeps arbitrary `properties` keys out while letting an administrator
    # extend the builder without a deploy.
    def self.dynamic_fields
      seen = {}
      MetadataSchema.active.each do |schema|
        schema.resolved_tabs.each do |tab|
          Array(tab["fields"]).each do |field|
            next unless field.is_a?(Hash)
            key = field["map_to_property"].presence
            # The same pattern the facet pipeline uses. A key that could contain
            # a quote must never reach a jsonb path expression.
            next unless key&.match?(/\A[\w:\-.]+\z/)
            next if by_name.key?(key) || Api::V1::SearchController::SYSTEM_PROPERTY_KEYS.include?(key)

            seen[key] ||= Field.new(
              name: key,
              label: field["label"].presence || key.humanize,
              type: SCHEMA_TYPE_MAP.fetch(field["field_type"], :string),
              source: :property, path: key, group: :metadata,
            )
          end
        end
      end
      seen.values.sort_by(&:name)
    rescue StandardError
      # The builder degrades to its static fields rather than 500-ing if the
      # schema tables are unreadable. A missing option is survivable; a search
      # page that will not load is not.
      []
    end

    # Static definitions win over dynamic ones of the same name, so an
    # administrator cannot redefine a core field and change how it compiles.
    def self.resolve(name)
      by_name[name.to_s] || dynamic_fields.find { |f| f.name == name.to_s }
    end

    def self.all
      definitions + dynamic_fields
    end
  end
end
