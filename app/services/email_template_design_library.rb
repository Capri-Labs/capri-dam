# Library of ready-made email designs surfaced in the "Choose a Template"
# gallery on the New Template drawer (Admin::EmailTemplatesController
# #design_templates). Selecting one prefills subject/html_body/text_body so
# non-technical admins can start from a polished layout instead of a blank
# textarea, then customize copy and variables from there.
#
# Every design intentionally uses table-based, inline-styled HTML (the only
# markup that renders consistently across email clients) so the output of
# the WYSIWYG editor stays compatible with Outlook/Gmail/Apple Mail.
class EmailTemplateDesignLibrary
  DESIGNS = [
    {
      id: "welcome_onboarding",
      name: "Welcome Onboarding",
      category: "transactional",
      description: "Warm welcome message with a clear call-to-action button.",
      subject: "Welcome to {{company.name}}, {{user.first_name}}!",
      html_body: <<~HTML,
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f7fb;padding:32px 0;">
          <tr><td align="center">
            <table role="presentation" width="480" cellpadding="0" cellspacing="0" style="background:#ffffff;border-radius:12px;overflow:hidden;font-family:Arial,Helvetica,sans-serif;">
              <tr><td style="background:#1a56db;padding:24px;text-align:center;">
                <h1 style="color:#ffffff;margin:0;font-size:22px;">{{company.name}}</h1>
              </td></tr>
              <tr><td style="padding:32px;">
                <h2 style="margin:0 0 12px;color:#121926;">Welcome, {{user.first_name}}!</h2>
                <p style="color:#4b5565;line-height:1.6;">Your account is ready. Sign in with {{user.email}} to start organizing and sharing your digital assets.</p>
                <table role="presentation" cellpadding="0" cellspacing="0" style="margin:24px 0;">
                  <tr><td style="background:#1a56db;border-radius:6px;">
                    <a href="{{app.url}}" style="display:inline-block;padding:12px 24px;color:#ffffff;text-decoration:none;font-weight:bold;">Get Started</a>
                  </td></tr>
                </table>
                <p style="color:#9aa4b2;font-size:12px;">If you didn't request this account, you can safely ignore this email.</p>
              </td></tr>
            </table>
          </td></tr>
        </table>
      HTML
      text_body: "Welcome, {{user.first_name}}!\n\nYour {{company.name}} account is ready. Sign in with {{user.email}} at {{app.url}} to get started.",
    },
    {
      id: "password_reset",
      name: "Password Reset",
      category: "transactional",
      description: "Security-focused reset link with expiry notice.",
      subject: "Reset your {{company.name}} password",
      html_body: <<~HTML,
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f7fb;padding:32px 0;">
          <tr><td align="center">
            <table role="presentation" width="480" cellpadding="0" cellspacing="0" style="background:#ffffff;border-radius:12px;font-family:Arial,Helvetica,sans-serif;">
              <tr><td style="padding:32px;">
                <h2 style="margin:0 0 12px;color:#121926;">Reset your password</h2>
                <p style="color:#4b5565;line-height:1.6;">Hi {{user.first_name}}, we received a request to reset your password. Click below to choose a new one.</p>
                <table role="presentation" cellpadding="0" cellspacing="0" style="margin:24px 0;">
                  <tr><td style="background:#e53e3e;border-radius:6px;">
                    <a href="{{reset.url}}" style="display:inline-block;padding:12px 24px;color:#ffffff;text-decoration:none;font-weight:bold;">Reset Password</a>
                  </td></tr>
                </table>
                <p style="color:#9aa4b2;font-size:12px;">This link expires in 1 hour. If you didn't request this, no action is needed.</p>
              </td></tr>
            </table>
          </td></tr>
        </table>
      HTML
      text_body: "Hi {{user.first_name}}, reset your password here: {{reset.url}} (expires in 1 hour).",
    },
    {
      id: "workflow_approval_request",
      name: "Workflow Approval Request",
      category: "notification",
      description: "Asks a reviewer to approve or reject a pending asset.",
      subject: "Approval needed: {{asset.name}}",
      html_body: <<~HTML,
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f7fb;padding:32px 0;">
          <tr><td align="center">
            <table role="presentation" width="480" cellpadding="0" cellspacing="0" style="background:#ffffff;border-radius:12px;font-family:Arial,Helvetica,sans-serif;">
              <tr><td style="padding:32px;">
                <h2 style="margin:0 0 12px;color:#121926;">Approval requested</h2>
                <p style="color:#4b5565;line-height:1.6;">{{user.first_name}}, <strong>{{asset.name}}</strong> in <strong>{{folder.name}}</strong> is waiting for your review.</p>
                <table role="presentation" cellpadding="0" cellspacing="0" style="margin:24px 0;">
                  <tr><td style="background:#0f9d58;border-radius:6px;">
                    <a href="{{workflow.url}}" style="display:inline-block;padding:12px 24px;color:#ffffff;text-decoration:none;font-weight:bold;">Review Now</a>
                  </td></tr>
                </table>
              </td></tr>
            </table>
          </td></tr>
        </table>
      HTML
      text_body: "{{user.first_name}}, {{asset.name}} in {{folder.name}} needs your review: {{workflow.url}}",
    },
    {
      id: "asset_published",
      name: "Asset Published Announcement",
      category: "notification",
      description: "Celebratory announcement when an asset goes live.",
      subject: "{{asset.name}} is now live",
      html_body: <<~HTML,
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f7fb;padding:32px 0;">
          <tr><td align="center">
            <table role="presentation" width="480" cellpadding="0" cellspacing="0" style="background:#ffffff;border-radius:12px;font-family:Arial,Helvetica,sans-serif;">
              <tr><td style="padding:32px;">
                <h2 style="margin:0 0 12px;color:#121926;">🎉 {{asset.name}} is live!</h2>
                <p style="color:#4b5565;line-height:1.6;">Published by {{published_by.name}}. View it anytime at the link below.</p>
                <table role="presentation" cellpadding="0" cellspacing="0" style="margin:24px 0;">
                  <tr><td style="background:#1a56db;border-radius:6px;">
                    <a href="{{asset.url}}" style="display:inline-block;padding:12px 24px;color:#ffffff;text-decoration:none;font-weight:bold;">View Asset</a>
                  </td></tr>
                </table>
              </td></tr>
            </table>
          </td></tr>
        </table>
      HTML
      text_body: "{{asset.name}} is now live, published by {{published_by.name}}. View: {{asset.url}}",
    },
    {
      id: "newsletter_digest",
      name: "Newsletter Digest",
      category: "announcement",
      description: "Multi-section roundup layout for periodic digests.",
      subject: "Your {{company.name}} digest for {{current_date}}",
      html_body: <<~HTML,
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f7fb;padding:32px 0;">
          <tr><td align="center">
            <table role="presentation" width="520" cellpadding="0" cellspacing="0" style="background:#ffffff;border-radius:12px;font-family:Arial,Helvetica,sans-serif;">
              <tr><td style="padding:32px;">
                <h2 style="margin:0 0 16px;color:#121926;">This week at {{company.name}}</h2>
                <p style="color:#4b5565;line-height:1.6;">Hi {{user.first_name}}, here is what changed since your last visit.</p>
                <hr style="border:none;border-top:1px solid #e3e8ef;margin:20px 0;" />
                <p style="color:#4b5565;line-height:1.6;">— New assets uploaded<br/>— Workflows completed<br/>— Storage usage summary</p>
              </td></tr>
            </table>
          </td></tr>
        </table>
      HTML
      text_body: "This week at {{company.name}}: new assets, completed workflows, and storage usage. Sign in for details: {{app.url}}",
    },
    {
      id: "event_invitation",
      name: "Event Invitation",
      category: "announcement",
      description: "Invitation card with date, time, and RSVP button.",
      subject: "You're invited: {{event.name}}",
      html_body: <<~HTML,
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f7fb;padding:32px 0;">
          <tr><td align="center">
            <table role="presentation" width="480" cellpadding="0" cellspacing="0" style="background:#ffffff;border-radius:12px;font-family:Arial,Helvetica,sans-serif;">
              <tr><td style="padding:32px;text-align:center;">
                <h2 style="margin:0 0 12px;color:#121926;">{{event.name}}</h2>
                <p style="color:#4b5565;line-height:1.6;">{{event.date}} at {{event.time}}</p>
                <table role="presentation" cellpadding="0" cellspacing="0" style="margin:24px auto;">
                  <tr><td style="background:#7c3aed;border-radius:6px;">
                    <a href="{{event.rsvp_url}}" style="display:inline-block;padding:12px 24px;color:#ffffff;text-decoration:none;font-weight:bold;">RSVP Now</a>
                  </td></tr>
                </table>
              </td></tr>
            </table>
          </td></tr>
        </table>
      HTML
      text_body: "You're invited to {{event.name}} on {{event.date}} at {{event.time}}. RSVP: {{event.rsvp_url}}",
    },
    {
      id: "product_update",
      name: "Product Update",
      category: "announcement",
      description: "Feature-highlight layout for release notes.",
      subject: "New in {{company.name}}: {{release.title}}",
      html_body: <<~HTML,
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f7fb;padding:32px 0;">
          <tr><td align="center">
            <table role="presentation" width="480" cellpadding="0" cellspacing="0" style="background:#ffffff;border-radius:12px;font-family:Arial,Helvetica,sans-serif;">
              <tr><td style="padding:32px;">
                <h2 style="margin:0 0 12px;color:#121926;">{{release.title}}</h2>
                <p style="color:#4b5565;line-height:1.6;">{{release.summary}}</p>
                <table role="presentation" cellpadding="0" cellspacing="0" style="margin:24px 0;">
                  <tr><td style="background:#1a56db;border-radius:6px;">
                    <a href="{{release.url}}" style="display:inline-block;padding:12px 24px;color:#ffffff;text-decoration:none;font-weight:bold;">See What's New</a>
                  </td></tr>
                </table>
              </td></tr>
            </table>
          </td></tr>
        </table>
      HTML
      text_body: "New in {{company.name}}: {{release.title}} - {{release.summary}}. Details: {{release.url}}",
    },
    {
      id: "system_maintenance_notice",
      name: "Maintenance Notice",
      category: "system",
      description: "Scheduled downtime warning with time window.",
      subject: "Scheduled maintenance: {{maintenance_start}} - {{maintenance_end}}",
      html_body: <<~HTML,
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f7fb;padding:32px 0;">
          <tr><td align="center">
            <table role="presentation" width="480" cellpadding="0" cellspacing="0" style="background:#fffbea;border:1px solid #f5c451;border-radius:12px;font-family:Arial,Helvetica,sans-serif;">
              <tr><td style="padding:32px;">
                <h2 style="margin:0 0 12px;color:#7a5b00;">⚠ Scheduled Maintenance</h2>
                <p style="color:#4b5565;line-height:1.6;">{{message}}</p>
                <p style="color:#4b5565;line-height:1.6;"><strong>Window:</strong> {{maintenance_start}} – {{maintenance_end}}</p>
              </td></tr>
            </table>
          </td></tr>
        </table>
      HTML
      text_body: "Scheduled maintenance from {{maintenance_start}} to {{maintenance_end}}. {{message}}",
    },
    {
      id: "team_invitation",
      name: "Team Invitation",
      category: "notification",
      description: "Invites a teammate to join a shared collection or group.",
      subject: "{{sender.name}} invited you to {{company.name}}",
      html_body: <<~HTML,
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f7fb;padding:32px 0;">
          <tr><td align="center">
            <table role="presentation" width="480" cellpadding="0" cellspacing="0" style="background:#ffffff;border-radius:12px;font-family:Arial,Helvetica,sans-serif;">
              <tr><td style="padding:32px;">
                <h2 style="margin:0 0 12px;color:#121926;">You've been invited</h2>
                <p style="color:#4b5565;line-height:1.6;">{{sender.name}} invited you to collaborate on {{company.name}}.</p>
                <table role="presentation" cellpadding="0" cellspacing="0" style="margin:24px 0;">
                  <tr><td style="background:#1a56db;border-radius:6px;">
                    <a href="{{invite.url}}" style="display:inline-block;padding:12px 24px;color:#ffffff;text-decoration:none;font-weight:bold;">Accept Invitation</a>
                  </td></tr>
                </table>
              </td></tr>
            </table>
          </td></tr>
        </table>
      HTML
      text_body: "{{sender.name}} invited you to {{company.name}}. Accept: {{invite.url}}",
    },
    {
      id: "confirmation_receipt",
      name: "Thank You / Confirmation",
      category: "transactional",
      description: "Generic confirmation receipt for a completed action.",
      subject: "Confirmed: {{action.name}}",
      html_body: <<~HTML,
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f7fb;padding:32px 0;">
          <tr><td align="center">
            <table role="presentation" width="480" cellpadding="0" cellspacing="0" style="background:#ffffff;border-radius:12px;font-family:Arial,Helvetica,sans-serif;">
              <tr><td style="padding:32px;text-align:center;">
                <h2 style="margin:0 0 12px;color:#0f9d58;">✔ Confirmed</h2>
                <p style="color:#4b5565;line-height:1.6;">Hi {{user.first_name}}, your request for <strong>{{action.name}}</strong> was completed successfully.</p>
                <p style="color:#9aa4b2;font-size:12px;">Questions? Contact {{company.support_email}}</p>
              </td></tr>
            </table>
          </td></tr>
        </table>
      HTML
      text_body: "Hi {{user.first_name}}, your request for {{action.name}} was completed successfully. Questions? {{company.support_email}}",
    },
  ].freeze
end
