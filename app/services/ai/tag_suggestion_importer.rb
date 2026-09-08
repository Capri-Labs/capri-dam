module Ai
  # Turns labels returned by the AI gateway into pending {AiTagSuggestion} rows.
  #
  # TRUST BOUNDARY
  # --------------
  # The gateway is a separate service, so its payload is untrusted input: every
  # label is normalised and length-checked, confidence is clamped and floored,
  # the list is capped, and a malformed entry is skipped rather than aborting
  # the import — one bad label should not discard nine good ones.
  #
  # WHAT IS DELIBERATELY THROWN AWAY
  # --------------------------------
  # Three classes of label never become a suggestion, because each would waste a
  # person's attention:
  #
  # * *Below the confidence floor* — a model unsure of what it saw produces
  #   triage fatigue, and a queue nobody reads is worse than no queue.
  # * *Already on the asset* — proposing a tag someone has already applied asks
  #   them to agree with themselves.
  # * *Previously dismissed* — a rejection is a decision. Re-proposing a label a
  #   person has already turned down would make that decision meaningless and
  #   the queue self-refilling.
  #
  # Nothing here writes to +assets.properties["tags"]+. Suggestions cross into
  # real tags only via {AiTagSuggestion#accept!}.
  class TagSuggestionImporter
    Result = Struct.new(:imported, :skipped, :errors, keyword_init: true)

    # @param run [AiTaggingRun]
    def initialize(run)
      @run   = run
      @asset = run.asset
    end

    # @param labels [Array<Hash>] raw labels from the gateway, e.g.
    #   [{ "label" => "sunset", "confidence" => 0.91 }]
    # @return [Result]
    def import(labels)
      imported = 0
      skipped  = 0
      errors   = []

      candidates = Array(labels).first(AiTaggingRun::MAX_SUGGESTIONS * 4)

      # One transaction for the whole run: a half-imported run would leave a
      # person triaging an incomplete picture with no way to tell.
      ActiveRecord::Base.transaction do
        accepted_labels = []

        candidates.each do |raw|
          break if imported >= AiTaggingRun::MAX_SUGGESTIONS

          label = AiTagSuggestion.normalise(extract_label(raw))
          confidence = extract_confidence(raw)

          if reject?(label, confidence, accepted_labels)
            skipped += 1
            next
          end

          AiTagSuggestion.create!(
            ai_tagging_run: @run,
            asset: @asset,
            label: label,
            confidence: confidence,
            state: "pending",
          )
          accepted_labels << label
          imported += 1
        rescue ActiveRecord::RecordInvalid => e
          skipped += 1
          errors << e.message
        end

        @run.complete!(imported)
      end

      Result.new(imported: imported, skipped: skipped, errors: errors)
    end

    private

    def reject?(label, confidence, seen)
      return true if label.blank? || label.length > 100
      return true if confidence.present? && confidence < AiTaggingRun::MIN_CONFIDENCE
      # Within one payload the gateway may repeat itself; the unique index would
      # raise, but catching it here keeps the run's own duplicates out of the
      # error list where they would look like a real problem.
      return true if seen.include?(label)
      return true if existing_tags.include?(label)
      return true if dismissed_labels.include?(label)

      false
    end

    # Compared in normalised form, so an asset tagged "Sunset" is not offered
    # "sunset" as though it were new.
    def existing_tags
      @existing_tags ||= begin
        props = @asset.properties.is_a?(Hash) ? @asset.properties : {}
        Array(props["tags"]).map { |t| AiTagSuggestion.normalise(t) }
      end
    end

    # Across every previous run for this asset, not just this one.
    def dismissed_labels
      @dismissed_labels ||=
        AiTagSuggestion.where(asset_id: @asset.id, state: "dismissed").pluck(:label).to_set
    end

    def extract_label(raw)
      return raw if raw.is_a?(String)

      hash = to_hash(raw)
      hash ? (hash["label"] || hash["tag"]) : nil
    end

    # Absent confidence is preserved as nil rather than defaulted: a model that
    # does not report confidence is not the same as one reporting zero, and
    # defaulting would either discard everything or bypass the floor entirely.
    def extract_confidence(raw)
      hash = to_hash(raw)
      return nil unless hash

      value = hash["confidence"] || hash["score"]
      return nil if value.nil?

      # Clamped rather than rejected: a gateway reporting 1.4 has a scaling bug,
      # but the label it found is probably still real.
      Float(value).clamp(0.0, 1.0)
    rescue ArgumentError, TypeError
      nil
    end

    # A form-encoded callback arrives as ActionController::Parameters, not Hash,
    # so a bare +is_a?(Hash)+ test would silently discard every label the
    # gateway sent. Both shapes are normalised to a string-keyed hash here.
    def to_hash(raw)
      return raw.to_unsafe_h.stringify_keys if raw.respond_to?(:to_unsafe_h)
      return raw.stringify_keys if raw.is_a?(Hash)

      nil
    end
  end
end
