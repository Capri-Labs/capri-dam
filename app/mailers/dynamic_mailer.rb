class DynamicMailer < ApplicationMailer
  # Uses the default from address you configured in your SMTP settings,
  # or falls back to a generic one if not set.
  default from: -> { SystemEmailConfig.current.from_address_with_name }

  def dispatch_email(to:, subject:, html_body:, text_body:)
    mail(to: to, subject: subject) do |format|
      # We use html_safe here because Liquid has already compiled the layout safely
      format.html { render html: html_body.html_safe }
      format.text { render plain: text_body }
    end
  end
end
