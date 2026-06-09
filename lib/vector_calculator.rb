module VectorCalculator
  def self.cosine_similarity(vec1, vec2)
    return 0.0 if vec1.nil? || vec2.nil? || vec1.empty? || vec2.empty?
    return 0.0 if vec1.length != vec2.length

    dot_product = 0.0
    norm_a = 0.0
    norm_b = 0.0

    vec1.each_with_index do |val1, index|
      val2 = vec2[index]
      dot_product += (val1 * val2)
      norm_a += (val1 ** 2)
      norm_b += (val2 ** 2)
    end

    magnitude = Math.sqrt(norm_a) * Math.sqrt(norm_b)
    return 0.0 if magnitude == 0.0

    dot_product / magnitude
  end
end