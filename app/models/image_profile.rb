# frozen_string_literal: true

# ImageProfile stores configuration for automatic image processing applied at upload time
# when the profile is assigned to a folder.
#
# Sections:
#   - Unsharp Mask  – fine-tune sharpening on downsampled renditions
#   - Crop Type     – 'none' | 'smart_crop'
#   - Responsive Image Crop – array of { name, width, height } breakpoints
#   - Color & Image Swatch  – thumbnail generation dimensions
#
# Image Profiles are NOT applicable to PDF, animated GIF, or INDD files.
class ImageProfile < ApplicationRecord
  # ── Associations ─────────────────────────────────────────────────────────────
  has_many :folder_assignments,
           class_name:  "ImageProfileFolderAssignment",
           dependent:   :destroy

  # ── Validations ──────────────────────────────────────────────────────────────
  validates :name,      presence: true
  validates :crop_type, inclusion: { in: %w[none smart_crop], message: "must be 'none' or 'smart_crop'" }

  validates :swatch_width,  numericality: { greater_than: 0, only_integer: true }, allow_nil: true
  validates :swatch_height, numericality: { greater_than: 0, only_integer: true }, allow_nil: true

  validate :unsharp_mask_values_in_range
  validate :responsive_crops_structure

  # ── Scopes ───────────────────────────────────────────────────────────────────
  scope :active, -> { where(deleted_at: nil) }

  # ── Soft Delete ───────────────────────────────────────────────────────────────
  def soft_delete!
    update!(deleted_at: Time.current)
  end

  # ── Helpers ───────────────────────────────────────────────────────────────────

  # Returns the configured unsharp mask with safe defaults.
  def effective_unsharp_mask
    defaults = { "amount" => 1.75, "radius" => 0.2, "threshold" => 2 }
    defaults.merge(unsharp_mask.presence || {})
  end

  # Determines whether a given MIME type supports image profile processing.
  # PDF, animated GIF, and INDD files are explicitly excluded.
  def self.applicable_mime_type?(mime)
    excluded = %w[application/pdf image/gif application/x-indesign application/indesign]
    return false if excluded.include?(mime.to_s.downcase)

    mime.to_s.start_with?("image/")
  end

  private

  def unsharp_mask_values_in_range
    return if unsharp_mask.blank?

    amount    = unsharp_mask["amount"].to_f
    radius    = unsharp_mask["radius"].to_f
    threshold = unsharp_mask["threshold"].to_i

    errors.add(:unsharp_mask, "amount must be between 0 and 5")    unless amount.between?(0, 5)
    errors.add(:unsharp_mask, "radius must be between 0 and 250")  unless radius.between?(0, 250)
    errors.add(:unsharp_mask, "threshold must be between 0 and 255") unless threshold.between?(0, 255)
  end

  def responsive_crops_structure
    return if responsive_crops.blank?
    return errors.add(:responsive_crops, "must be an array") unless responsive_crops.is_a?(Array)

    responsive_crops.each_with_index do |crop, i|
      unless crop.is_a?(Hash) && crop["name"].present? &&
             crop["width"].to_i > 0 && crop["height"].to_i > 0
        errors.add(:responsive_crops, "entry #{i + 1} must have name, width > 0, and height > 0")
      end
    end
  end
end
