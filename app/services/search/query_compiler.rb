# frozen_string_literal: true

module Search
  # Compiles a nested boolean query AST into a single `WHERE` fragment.
  #
  # The AST has exactly two node shapes:
  #
  #   group: { "op" => "and" | "or" | "not", "children" => [ node, ... ] }
  #   leaf:  { "field" => "title", "operator" => "contains", "value" => "sunset" }
  #
  # This is the *only* place an AST becomes SQL. Every field name is resolved
  # through {FieldRegistry} and every value arrives as a bind parameter, so a
  # caller can influence what is compared but never the shape of the query.
  #
  # == Why a compiler rather than more flat params
  #
  # The flat params on the search endpoint are implicitly AND-ed. That is fine
  # for a facet bar, where every control narrows the result, but it cannot
  # express `(shot_on_location OR studio) AND NOT expired` — and no amount of
  # additional flat params ever will, because the missing thing is *structure*,
  # not vocabulary.
  #
  # == Why the limits are not optional
  #
  # An AST is caller-supplied structure, and structure recurses. Without a depth
  # and node cap, a few kilobytes of nested JSON becomes a query with thousands
  # of predicates: a denial-of-service that costs the attacker nothing and the
  # database everything. {MAX_DEPTH} and {MAX_NODES} are checked during the walk,
  # before any SQL is produced.
  class QueryCompiler
    # Raised for any malformed, over-large, or disallowed query. Carries the
    # path to the offending node so the builder UI can point at it rather than
    # showing a single unhelpful banner.
    class InvalidQuery < StandardError
      attr_reader :path

      def initialize(message, path = [])
        @path = path
        super(path.empty? ? message : "#{message} (at #{path.join(".")})")
      end
    end

    MAX_DEPTH = 8
    MAX_NODES = 100
    MAX_VALUE_LENGTH = 500
    MAX_LIST_VALUES = 50

    GROUP_OPS = %w[and or not].freeze

    # Values Postgres and the metadata pipeline treat as true. Anything else is
    # false — including absent, which is the only reading that makes a missing
    # key behave like an unticked box.
    TRUE_VALUES = %w[true t 1 yes on].freeze

    # Guards for property casts. `properties` is untyped, so a single row whose
    # `file_size` holds "unknown" would abort the whole query with a cast error.
    # These CASE expressions are short-circuit-safe in a way a bare
    # `(properties->>'x')::numeric` combined with an `AND` guard is not:
    # Postgres does not promise to evaluate AND operands left to right.
    # NOTE: `?` is deliberately absent from these patterns — `sanitize_sql_array`
    # counts every `?` in the fragment as a bind placeholder, so a `?` quantifier
    # here would be read as a parameter and the query would fail to build.
    # `{0,1}` says the same thing without colliding.
    NUMERIC_PATTERN   = '^-{0,1}[0-9]+(\.[0-9]+){0,1}$'
    TIMESTAMP_PATTERN = "^[0-9]{4}-[0-9]{2}-[0-9]{2}"

    UUID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

    # A well-formed uuid that no entity will ever have, so a filter naming only
    # unresolvable entities matches nothing. Returning an empty list instead
    # would produce `IN ()` — a syntax error — and dropping the predicate
    # entirely would match *everything*, which is the dangerous direction for a
    # filter to fail in.
    NO_ENTITY_ID = "00000000-0000-0000-0000-000000000000"

    def initialize(ast)
      @ast = ast
      @node_count = 0
    end

    # @param scope [ActiveRecord::Relation]
    # @return [ActiveRecord::Relation]
    def apply(scope)
      sql, binds = compile
      return scope if sql.nil?

      scope.where(Asset.sanitize_sql_array([ sql, *binds ]))
    end

    # @return [Array(String, Array), Array(nil, nil)] fragment and its binds,
    #   or a nil pair when the AST imposes no constraint at all.
    def compile
      node = normalise_node(@ast, [])
      return [ nil, nil ] if node.nil?

      compile_node(node, [], 0)
    end

    private

    # -- Walk -----------------------------------------------------------------

    def compile_node(node, path, depth)
      raise InvalidQuery.new("Query is nested too deeply (max #{MAX_DEPTH})", path) if depth > MAX_DEPTH

      @node_count += 1
      raise InvalidQuery.new("Query has too many conditions (max #{MAX_NODES})", path) if @node_count > MAX_NODES

      if node.key?("op")
        compile_group(node, path, depth)
      elsif node.key?("field")
        compile_leaf(node, path)
      else
        raise InvalidQuery.new("Node must have either 'op' or 'field'", path)
      end
    end

    def compile_group(node, path, depth)
      op = node["op"].to_s.downcase
      raise InvalidQuery.new("Unknown operator '#{node["op"]}'", path) unless GROUP_OPS.include?(op)

      children = node["children"]
      raise InvalidQuery.new("'children' must be an array", path) unless children.is_a?(Array)

      compiled = children.each_with_index.filter_map do |child, index|
        child_node = normalise_node(child, path + [ "children", index.to_s ])
        next if child_node.nil?

        compile_node(child_node, path + [ "children", index.to_s ], depth + 1)
      end

      if op == "not"
        # NOT takes exactly one child. Allowing several would force a reading —
        # "not all of these" or "none of these" — onto a structure that does not
        # state which, and the two differ on every partially-matching row.
        raise InvalidQuery.new("'not' takes exactly one condition", path) unless compiled.length == 1

        sql, binds = compiled.first
        return [ "NOT (#{sql})", binds ]
      end

      # An empty group is not a contradiction, it is an unfinished one. A user
      # who has added a group but no conditions yet should see everything, not
      # nothing — so an empty OR is a no-op like an empty AND, rather than the
      # logically-pure `FALSE`.
      return nil_constraint if compiled.empty?

      joiner = op == "or" ? " OR " : " AND "
      [ "(#{compiled.map(&:first).join(joiner)})", compiled.flat_map(&:last) ]
    end

    # -- Leaves ---------------------------------------------------------------

    def compile_leaf(node, path)
      field = FieldRegistry.resolve(node["field"].to_s)
      raise InvalidQuery.new("Unknown field '#{node["field"]}'", path) if field.nil?

      operator = node["operator"].to_s.downcase
      allowed = FieldRegistry.operators_for(field.type)
      unless allowed.include?(operator)
        raise InvalidQuery.new("Operator '#{operator}' is not valid for field '#{field.name}'", path)
      end

      value = node["value"]
      case field.type
      when :number   then number_predicate(field, operator, value, path)
      when :datetime then datetime_predicate(field, operator, value, path)
      when :boolean  then boolean_predicate(field, operator, value, path)
      when :array    then array_predicate(field, operator, value, path)
      when :entity   then entity_predicate(field, operator, value, path)
      else                text_predicate(field, operator, value, path)
      end
    end

    def text_predicate(field, operator, value, path)
      expr = text_expression(field)

      case operator
      when "present" then [ "(#{expr} IS NOT NULL AND #{expr} <> '')", [] ]
      when "blank"   then [ "(#{expr} IS NULL OR #{expr} = '')", [] ]
      when "eq"      then [ "#{expr} = ?", [ scalar(value, path) ] ]
      # `IS DISTINCT FROM` rather than `<>`: a row where the field is absent is
      # genuinely "not equal to sunset", and plain `<>` would drop it because
      # NULL <> 'sunset' is NULL. Excluding unfilled rows from a negation is
      # the single most surprising thing a query builder can do.
      when "not_eq"  then [ "#{expr} IS DISTINCT FROM ?", [ scalar(value, path) ] ]
      when "contains"     then [ "#{expr} ILIKE ?", [ "%#{like_escape(scalar(value, path))}%" ] ]
      when "starts_with"  then [ "#{expr} ILIKE ?", [ "#{like_escape(scalar(value, path))}%" ] ]
      when "ends_with"    then [ "#{expr} ILIKE ?", [ "%#{like_escape(scalar(value, path))}" ] ]
      when "not_contains"
        [ "(#{expr} IS NULL OR #{expr} NOT ILIKE ?)", [ "%#{like_escape(scalar(value, path))}%" ] ]
      when "in"     then [ "#{expr} IN (?)", [ list(value, path) ] ]
      when "not_in" then [ "(#{expr} IS NULL OR #{expr} NOT IN (?))", [ list(value, path) ] ]
      else raise InvalidQuery.new("Unsupported operator '#{operator}'", path)
      end
    end

    def number_predicate(field, operator, value, path)
      expr = numeric_expression(field)

      case operator
      when "present" then [ "#{expr} IS NOT NULL", [] ]
      when "blank"   then [ "#{expr} IS NULL", [] ]
      when "between"
        low, high = range(value, path)
        [ "#{expr} BETWEEN ? AND ?", [ numeric(low, path), numeric(high, path) ] ]
      when "eq"     then [ "#{expr} = ?", [ numeric(value, path) ] ]
      when "not_eq" then [ "#{expr} IS DISTINCT FROM ?", [ numeric(value, path) ] ]
      when "gt"     then [ "#{expr} > ?",  [ numeric(value, path) ] ]
      when "gte"    then [ "#{expr} >= ?", [ numeric(value, path) ] ]
      when "lt"     then [ "#{expr} < ?",  [ numeric(value, path) ] ]
      when "lte"    then [ "#{expr} <= ?", [ numeric(value, path) ] ]
      else raise InvalidQuery.new("Unsupported operator '#{operator}'", path)
      end
    end

    def datetime_predicate(field, operator, value, path)
      expr = timestamp_expression(field)

      case operator
      when "present" then [ "#{expr} IS NOT NULL", [] ]
      when "blank"   then [ "#{expr} IS NULL", [] ]
      when "before"  then [ "#{expr} < ?", [ timestamp(value, path) ] ]
      when "after"   then [ "#{expr} > ?", [ timestamp(value, path) ] ]
      when "between"
        low, high = range(value, path)
        [ "#{expr} BETWEEN ? AND ?", [ timestamp(low, path), timestamp(high, path) ] ]
      when "eq"
        # "On this date" is what a person means by an equal date; an exact
        # timestamp match would practically never be true and would read as a
        # broken filter rather than a precise one.
        day = timestamp(value, path)
        [ "(#{expr} >= ? AND #{expr} < ?)", [ day.beginning_of_day, day.beginning_of_day + 1.day ] ]
      else raise InvalidQuery.new("Unsupported operator '#{operator}'", path)
      end
    end

    def boolean_predicate(field, operator, value, path)
      expr = text_expression(field)

      case operator
      when "present" then [ "(#{expr} IS NOT NULL AND #{expr} <> '')", [] ]
      when "blank"   then [ "(#{expr} IS NULL OR #{expr} = '')", [] ]
      when "eq"
        wanted = TRUE_VALUES.include?(scalar(value, path).to_s.downcase)
        if wanted
          [ "lower(#{expr}) IN (?)", [ TRUE_VALUES ] ]
        else
          # An absent key reads as false: an unticked box and a box that was
          # never rendered are indistinguishable to the person searching.
          [ "(#{expr} IS NULL OR lower(#{expr}) NOT IN (?))", [ TRUE_VALUES ] ]
        end
      else raise InvalidQuery.new("Unsupported operator '#{operator}'", path)
      end
    end

    def array_predicate(field, operator, value, path)
      unless field.source == :property
        raise InvalidQuery.new("Field '#{field.name}' is not a list", path)
      end

      # `jsonb_array_elements_text` raises if the value is not an array, and
      # `properties` carries no guarantee that it is — a hand-edited asset could
      # hold a bare string under `tags`. The CASE coerces those to an empty
      # array so one malformed row cannot fail the whole search.
      elements = <<~SQL.squish
        jsonb_array_elements_text(
          CASE WHEN jsonb_typeof(assets.properties->'#{field.path}') = 'array'
               THEN assets.properties->'#{field.path}'
               ELSE '[]'::jsonb END
        )
      SQL

      case operator
      when "present" then [ "EXISTS (SELECT 1 FROM #{elements} AS e(v))", [] ]
      when "blank"   then [ "NOT EXISTS (SELECT 1 FROM #{elements} AS e(v))", [] ]
      when "has_any"
        [ "EXISTS (SELECT 1 FROM #{elements} AS e(v) WHERE lower(e.v) IN (?))", [ downcased(value, path) ] ]
      when "none_of"
        [ "NOT EXISTS (SELECT 1 FROM #{elements} AS e(v) WHERE lower(e.v) IN (?))", [ downcased(value, path) ] ]
      when "has_all"
        wanted = downcased(value, path)
        [
          "(SELECT COUNT(DISTINCT lower(e.v)) FROM #{elements} AS e(v) WHERE lower(e.v) IN (?)) = ?",
          [ wanted, wanted.length ],
        ]
      else raise InvalidQuery.new("Unsupported operator '#{operator}'", path)
      end
    end

    # Entity links live in their own table, so unlike every other field type
    # this compiles to a correlated EXISTS rather than an expression over
    # `assets`. A join would have been the obvious alternative and is wrong
    # here: the compiler returns a WHERE fragment that callers apply to a scope
    # they own, and a join would silently multiply their rows.
    def entity_predicate(field, operator, value, path)
      relationship = field.path == "any" ? nil : field.path
      link = "asset_entities ae"
      correlate = "ae.asset_id = assets.id"
      correlate += " AND ae.relationship = '#{relationship}'" if relationship

      case operator
      when "present" then [ "EXISTS (SELECT 1 FROM #{link} WHERE #{correlate})", [] ]
      when "blank"   then [ "NOT EXISTS (SELECT 1 FROM #{link} WHERE #{correlate})", [] ]
      when "has_any"
        ids = entity_ids(value, path)
        [ "EXISTS (SELECT 1 FROM #{link} WHERE #{correlate} AND ae.entity_id IN (?))", [ ids ] ]
      when "none_of"
        ids = entity_ids(value, path)
        [ "NOT EXISTS (SELECT 1 FROM #{link} WHERE #{correlate} AND ae.entity_id IN (?))", [ ids ] ]
      when "has_all"
        ids = entity_ids(value, path)
        [
          "(SELECT COUNT(DISTINCT ae.entity_id) FROM #{link} WHERE #{correlate} AND ae.entity_id IN (?)) = ?",
          [ ids, ids.length ],
        ]
      else raise InvalidQuery.new("Unsupported operator '#{operator}'", path)
      end
    end

    # Turns caller-supplied entity references into entity ids.
    #
    # A reference is a UUID or a type-qualified slug (`person:jane-doe`). A bare
    # slug is rejected on purpose: "berlin" is ambiguous across a place, a
    # person and a campaign, and silently picking one would reintroduce, inside
    # the entity layer, precisely the collapse that the entity layer exists to
    # remove. The error names the alternative rather than just refusing.
    #
    # References are resolved through the merge chain, so a query written
    # against an entity that has since been merged away still finds the assets
    # whose links moved to the survivor. Without this, cleaning up duplicates
    # would silently break every saved search that named one.
    def entity_ids(value, path)
      references = list(value, path)

      resolved = references.filter_map { |reference| resolve_entity_reference(reference, path) }

      # An IN () with no members is a syntax error, and an unresolvable
      # reference should match nothing rather than everything.
      resolved.presence || [ NO_ENTITY_ID ]
    end

    def resolve_entity_reference(reference, path)
      reference = reference.to_s.strip
      entity =
        if reference.match?(UUID_PATTERN)
          Entity.find_by(id: reference)
        elsif reference.include?(":")
          entity_type, slug = reference.split(":", 2)
          Entity.find_by(entity_type: entity_type, slug: slug)
        else
          raise InvalidQuery.new(
            "Entity reference '#{reference}' is ambiguous; use an id or a qualified slug such as 'person:#{reference}'",
            path,
          )
        end

      entity&.canonical_entity&.id
    end

    # -- Expressions ----------------------------------------------------------

    def text_expression(field)
      # Field paths are never caller-supplied: they come from the registry,
      # whose dynamic entries are themselves filtered through `\A[\w:\-.]+\z`.
      # That is what makes interpolating them here safe, and why nothing else
      # may be.
      if field.source == :column
        "assets.#{field.path}::text"
      else
        "assets.properties->>'#{field.path}'"
      end
    end

    def numeric_expression(field)
      return "assets.#{field.path}" if field.source == :column

      raw = "assets.properties->>'#{field.path}'"
      "(CASE WHEN #{raw} ~ '#{NUMERIC_PATTERN}' THEN (#{raw})::numeric ELSE NULL END)"
    end

    def timestamp_expression(field)
      return "assets.#{field.path}" if field.source == :column

      raw = "assets.properties->>'#{field.path}'"
      "(CASE WHEN #{raw} ~ '#{TIMESTAMP_PATTERN}' THEN (#{raw})::timestamptz ELSE NULL END)"
    end

    # -- Value coercion -------------------------------------------------------

    def normalise_node(node, path)
      node = node.to_unsafe_h if node.respond_to?(:to_unsafe_h)
      return nil if node.nil?
      raise InvalidQuery.new("Each condition must be an object", path) unless node.is_a?(Hash)

      node = node.stringify_keys
      node.empty? ? nil : node
    end

    def nil_constraint
      [ "1=1", [] ]
    end

    def scalar(value, path)
      raise InvalidQuery.new("A value is required", path) if value.nil?
      raise InvalidQuery.new("Value must be a single value, not a list", path) if value.is_a?(Array)

      string = value.to_s
      raise InvalidQuery.new("Value is too long (max #{MAX_VALUE_LENGTH})", path) if string.length > MAX_VALUE_LENGTH

      string
    end

    def list(value, path)
      values = Array.wrap(value).map { |v| v.to_s }.reject(&:blank?).uniq
      raise InvalidQuery.new("A non-empty list of values is required", path) if values.empty?
      raise InvalidQuery.new("Too many values (max #{MAX_LIST_VALUES})", path) if values.length > MAX_LIST_VALUES
      if values.any? { |v| v.length > MAX_VALUE_LENGTH }
        raise InvalidQuery.new("Value is too long (max #{MAX_VALUE_LENGTH})", path)
      end

      values
    end

    def downcased(value, path)
      list(value, path).map(&:downcase)
    end

    def range(value, path)
      values = value.is_a?(Hash) ? [ value["from"] || value[:from], value["to"] || value[:to] ] : Array.wrap(value)
      raise InvalidQuery.new("'between' needs two values", path) unless values.compact.length == 2

      values
    end

    def numeric(value, path)
      Float(value.to_s)
    rescue ArgumentError, TypeError
      raise InvalidQuery.new("'#{value}' is not a number", path)
    end

    def timestamp(value, path)
      parsed = Time.zone.parse(value.to_s)
      raise InvalidQuery.new("'#{value}' is not a date", path) if parsed.nil?

      parsed
    rescue ArgumentError
      raise InvalidQuery.new("'#{value}' is not a date", path)
    end

    # `LIKE` gives `%` and `_` meaning. A user typing "50%_off" into a contains
    # box means those characters literally; without escaping, the query silently
    # matches far more than they asked for.
    def like_escape(string)
      string.gsub(/[\\%_]/) { |c| "\\#{c}" }
    end
  end
end
