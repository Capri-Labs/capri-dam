# Pure-Ruby utility module for cosine similarity calculations.
#
# Used internally for semantic-search scoring without requiring a database
# round-trip.  The primary production path uses pgvector via the +neighbor+
# gem ({Asset.nearest_to_vector}); this module is available as a lightweight
# fallback for in-memory comparisons (e.g. unit tests, batch pre-flight
# analysis).
#
# @example
#   vec_a = [0.1, 0.2, 0.3]
#   vec_b = [0.1, 0.2, 0.3]
#   VectorCalculator.cosine_similarity(vec_a, vec_b)  # => 1.0
#
# @see Asset.nearest_to_vector
module VectorCalculator
  # Computes the cosine similarity between two real-valued vectors.
  #
  # Returns +0.0+ (not an error) in any degenerate case:
  # * either vector is +nil+ or empty
  # * the vectors have different lengths
  # * either vector has zero magnitude (prevents division by zero)
  #
  # @param vec1 [Array<Numeric>] the first embedding vector
  # @param vec2 [Array<Numeric>] the second embedding vector
  # @return [Float] a value in the range [−1.0, 1.0]; +1.0+ means identical
  #   direction, +0.0+ means orthogonal, −1.0 means opposite
  def self.cosine_similarity(vec1, vec2)
    return 0.0 if vec1.nil? || vec2.nil? || vec1.empty? || vec2.empty?
    return 0.0 if vec1.length != vec2.length

    dot_product = 0.0
    norm_a      = 0.0
    norm_b      = 0.0

    vec1.each_with_index do |val1, index|
      val2         = vec2[index]
      dot_product += (val1 * val2)
      norm_a      += (val1 ** 2)
      norm_b      += (val2 ** 2)
    end

    magnitude = Math.sqrt(norm_a) * Math.sqrt(norm_b)
    return 0.0 if magnitude == 0.0

    dot_product / magnitude
  end
end