# Strongly-typed data mapper around the `email_brand_settings` row stored in
# the `settings` table (mirrors SystemEmailConfig's SMTP mapper). Surfaced on
# the "Communication Engine" tab of the Email Engine admin UI, this is the
# single source of truth for the custom CSS every outbound system email is
# themed with -- EmailDispatcherWorker injects `custom_css` as a `<style>`
# block into every rendered template (live triggers and "Send test" alike),
# so brand colors/fonts stay consistent across the whole notification
# framework without editing each individual template.
class EmailBrandSettings
  include ActiveModel::Model
  include ActiveModel::Attributes

  SETTINGS_KEY = "email_brand_settings".freeze
  MAX_CSS_LENGTH = 20_000

  attribute :custom_css, :string, default: ""
  attribute :primary_color, :string, default: "#1a56db"
  attribute :font_family, :string, default: "Arial, Helvetica, sans-serif"

  validates :custom_css, length: { maximum: MAX_CSS_LENGTH }
  validate :custom_css_must_not_contain_script_tags
  validates :primary_color, format: { with: /\A#(?:[0-9a-fA-F]{3}){1,2}\z/ }, allow_blank: true

  def self.current
    from_raw(Setting.get(SETTINGS_KEY))
  end

  def self.from_raw(raw)
    raw = raw.is_a?(Hash) ? raw.stringify_keys : {}

    new(
      custom_css: raw["custom_css"].to_s,
      primary_color: raw["primary_color"].presence || "#1a56db",
      font_family: raw["font_family"].presence || "Arial, Helvetica, sans-serif"
    )
  end

  def persist!
    return false unless valid?

    Setting.set(SETTINGS_KEY, to_settings_hash)
    true
  end

  def to_settings_hash
    {
      "custom_css" => custom_css.to_s,
      "primary_color" => primary_color,
      "font_family" => font_family,
    }
  end

  # Wraps the configured CSS in a `<style>` tag ready to be prepended to any
  # rendered email HTML body. Returns an empty string when no CSS is
  # configured so callers can safely concatenate the result unconditionally.
  def style_block
    return "" if custom_css.blank?

    "<style type=\"text/css\">\n#{custom_css}\n</style>\n"
  end

  def persisted?
    true
  end

  private

  # Defensive guard: this field must only ever contain CSS. Rejecting
  # `<script>` up front stops it from ever being persisted as an XSS vector,
  # even though it is only ever rendered inside a `<style>` tag downstream.
  def custom_css_must_not_contain_script_tags
    return if custom_css.blank?

    errors.add(:custom_css, "must not contain <script> tags") if custom_css =~ /<\s*script/i
  end
end
