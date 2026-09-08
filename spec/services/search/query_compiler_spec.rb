# frozen_string_literal: true

require "rails_helper"

RSpec.describe Search::QueryCompiler do
  def compile(ast, scope: Asset.all)
    described_class.new(ast).apply(scope)
  end

  def ids(ast)
    compile(ast).pluck(:id)
  end

  let(:folder) { create(:folder) }

  let!(:sunset) do
    create(:asset, title: "Sunset over Rome", folder: folder, status: :approved,
                   properties: { "content_type" => "image/jpeg", "file_size" => "2048",
                                 "width" => "1920", "height" => "1080",
                                 "tags" => %w[Travel Sunset] })
  end

  let!(:studio) do
    create(:asset, title: "Studio portrait", folder: folder, status: :ready,
                   properties: { "content_type" => "image/png", "file_size" => "512",
                                 "width" => "800", "height" => "1200",
                                 "tags" => %w[portrait studio] })
  end

  let!(:untagged) do
    create(:asset, title: "Scan 001", folder: folder, status: :draft,
                   properties: { "content_type" => "application/pdf" })
  end

  describe "an absent query" do
    it "imposes no constraint at all" do
      expect(compile(nil).count).to eq(3)
    end

    it "treats an empty group as unfinished rather than contradictory" do
      # An empty OR is logically false, but in a builder it means the user has
      # added a group and not filled it in yet.
      expect(ids({ "op" => "or", "children" => [] }).size).to eq(3)
    end
  end

  describe "boolean structure" do
    it "ANDs children" do
      result = ids({ "op" => "and", "children" => [
        { "field" => "title", "operator" => "contains", "value" => "s" },
        { "field" => "status", "operator" => "eq", "value" => "approved" },
      ] })
      expect(result).to contain_exactly(sunset.id)
    end

    it "ORs children" do
      result = ids({ "op" => "or", "children" => [
        { "field" => "status", "operator" => "eq", "value" => "approved" },
        { "field" => "status", "operator" => "eq", "value" => "draft" },
      ] })
      expect(result).to contain_exactly(sunset.id, untagged.id)
    end

    it "expresses (a OR b) AND NOT c — the thing flat params cannot" do
      result = ids({ "op" => "and", "children" => [
        { "op" => "or", "children" => [
          { "field" => "content_type", "operator" => "eq", "value" => "image/jpeg" },
          { "field" => "content_type", "operator" => "eq", "value" => "image/png" },
        ] },
        { "op" => "not", "children" => [
          { "field" => "status", "operator" => "eq", "value" => "approved" },
        ] },
      ] })
      expect(result).to contain_exactly(studio.id)
    end

    it "refuses a NOT with more than one child, rather than guessing a reading" do
      expect {
        ids({ "op" => "not", "children" => [
          { "field" => "status", "operator" => "eq", "value" => "draft" },
          { "field" => "status", "operator" => "eq", "value" => "ready" },
        ] })
      }.to raise_error(described_class::InvalidQuery, /exactly one/)
    end
  end

  describe "limits" do
    it "rejects an AST nested past the depth cap" do
      deepest = { "field" => "title", "operator" => "eq", "value" => "x" }
      ast = (described_class::MAX_DEPTH + 2).times.inject(deepest) do |inner, _|
        { "op" => "and", "children" => [ inner ] }
      end
      expect { ids(ast) }.to raise_error(described_class::InvalidQuery, /too deeply/)
    end

    it "rejects an AST with more nodes than the cap" do
      children = Array.new(described_class::MAX_NODES + 1) do
        { "field" => "title", "operator" => "eq", "value" => "x" }
      end
      expect { ids({ "op" => "and", "children" => children }) }
        .to raise_error(described_class::InvalidQuery, /too many conditions/)
    end

    it "caps the size of an IN list" do
      values = Array.new(described_class::MAX_LIST_VALUES + 1) { |i| "v#{i}" }
      expect { ids({ "field" => "title", "operator" => "in", "value" => values }) }
        .to raise_error(described_class::InvalidQuery, /Too many values/)
    end
  end

  describe "the field allow-list" do
    it "refuses a field that is not registered" do
      expect { ids({ "field" => "checksum_sha256", "operator" => "eq", "value" => "x" }) }
        .to raise_error(described_class::InvalidQuery, /Unknown field/)
    end

    it "refuses an operator the field's type does not offer" do
      expect { ids({ "field" => "created_at", "operator" => "contains", "value" => "x" }) }
        .to raise_error(described_class::InvalidQuery, /not valid for field/)
    end

    it "reports the path to the offending node so the UI can point at it" do
      ids({ "op" => "and", "children" => [ { "field" => "nope", "operator" => "eq", "value" => 1 } ] })
    rescue described_class::InvalidQuery => e
      expect(e.path).to eq(%w[children 0])
    end
  end

  describe "text operators" do
    it "matches contains case-insensitively" do
      expect(ids({ "field" => "title", "operator" => "contains", "value" => "SUNSET" }))
        .to contain_exactly(sunset.id)
    end

    it "treats LIKE wildcards in the value as literal characters" do
      create(:asset, title: "100% cotton", folder: folder)
      create(:asset, title: "100X cotton", folder: folder)

      expect(compile({ "field" => "title", "operator" => "contains", "value" => "100%" }).count).to eq(1)
    end

    it "includes rows where the field is absent when negating" do
      # `<>` would silently drop the untagged asset, because NULL <> 'x' is NULL.
      # Excluding unfilled rows from a negation is the most surprising thing a
      # builder can do.
      result = ids({ "field" => "content_type", "operator" => "not_eq", "value" => "image/jpeg" })
      expect(result).to contain_exactly(studio.id, untagged.id)
    end

    it "supports in and not_in" do
      expect(ids({ "field" => "status", "operator" => "in", "value" => %w[approved draft] }))
        .to contain_exactly(sunset.id, untagged.id)
    end

    it "distinguishes present from blank" do
      expect(ids({ "field" => "width", "operator" => "present" }))
        .to contain_exactly(sunset.id, studio.id)
      expect(ids({ "field" => "width", "operator" => "blank" }))
        .to contain_exactly(untagged.id)
    end
  end

  describe "number operators" do
    it "compares numerically, not lexically" do
      # "512" > "2048" as text; the cast is what makes this correct.
      expect(ids({ "field" => "file_size", "operator" => "gt", "value" => 1000 }))
        .to contain_exactly(sunset.id)
    end

    it "supports between" do
      expect(ids({ "field" => "file_size", "operator" => "between", "value" => [ 100, 1000 ] }))
        .to contain_exactly(studio.id)
    end

    it "survives a row whose value is not a number at all" do
      create(:asset, title: "Corrupt", folder: folder, properties: { "file_size" => "unknown" })
      expect { compile({ "field" => "file_size", "operator" => "gt", "value" => 1 }).count }
        .not_to raise_error
    end

    it "rejects a non-numeric operand" do
      expect { ids({ "field" => "file_size", "operator" => "gt", "value" => "big" }) }
        .to raise_error(described_class::InvalidQuery, /is not a number/)
    end
  end

  describe "datetime operators" do
    it "compares against a parsed timestamp" do
      sunset.update!(created_at: 3.days.ago)
      result = ids({ "field" => "created_at", "operator" => "before", "value" => 1.day.ago.iso8601 })
      expect(result).to include(sunset.id)
      expect(result).not_to include(studio.id)
    end

    it "reads eq as 'on that day' rather than an exact instant" do
      sunset.update!(created_at: Time.zone.parse("2026-03-04 14:22:07"))
      expect(ids({ "field" => "created_at", "operator" => "eq", "value" => "2026-03-04" }))
        .to contain_exactly(sunset.id)
    end

    it "rejects an unparseable date" do
      expect { ids({ "field" => "created_at", "operator" => "after", "value" => "yesterdayish" }) }
        .to raise_error(described_class::InvalidQuery, /is not a date/)
    end
  end

  describe "tag list operators" do
    it "matches any of the listed tags, case-insensitively" do
      expect(ids({ "field" => "tags", "operator" => "has_any", "value" => %w[sunset studio] }))
        .to contain_exactly(sunset.id, studio.id)
    end

    it "requires every listed tag for has_all" do
      expect(ids({ "field" => "tags", "operator" => "has_all", "value" => %w[travel sunset] }))
        .to contain_exactly(sunset.id)
      expect(ids({ "field" => "tags", "operator" => "has_all", "value" => %w[travel portrait] }))
        .to be_empty
    end

    it "excludes matches for none_of, and keeps assets with no tags at all" do
      expect(ids({ "field" => "tags", "operator" => "none_of", "value" => %w[sunset] }))
        .to contain_exactly(studio.id, untagged.id)
    end

    it "survives a row where the tags key is not an array" do
      create(:asset, title: "Odd", folder: folder, properties: { "tags" => "just-a-string" })
      expect { compile({ "field" => "tags", "operator" => "has_any", "value" => %w[x] }).count }
        .not_to raise_error
    end
  end

  describe "malformed input" do
    it "rejects a node that is neither a group nor a leaf" do
      expect { ids({ "nonsense" => true }) }
        .to raise_error(described_class::InvalidQuery, /either 'op' or 'field'/)
    end

    it "rejects an unknown group operator" do
      expect { ids({ "op" => "xor", "children" => [] }) }
        .to raise_error(described_class::InvalidQuery, /Unknown operator/)
    end

    it "rejects children that are not an array" do
      expect { ids({ "op" => "and", "children" => "nope" }) }
        .to raise_error(described_class::InvalidQuery, /must be an array/)
    end

    it "rejects an over-long value" do
      expect { ids({ "field" => "title", "operator" => "eq", "value" => "a" * 501 }) }
        .to raise_error(described_class::InvalidQuery, /too long/)
    end

    it "accepts ActionController::Parameters as well as a plain Hash" do
      params = ActionController::Parameters.new(
        field: "status", operator: "eq", value: "approved",
      )
      expect(ids(params)).to contain_exactly(sunset.id)
    end
  end
end
