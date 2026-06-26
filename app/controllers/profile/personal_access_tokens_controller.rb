# REST API for Personal Access Tokens.
#
# All actions operate on the *current user's own* tokens only.
# Routes live under /profile/personal_access_tokens.
class Profile::PersonalAccessTokensController < ApplicationController
  before_action :authenticate_user!

  # GET /profile/personal_access_tokens.json
  def index
    tokens = current_user.personal_access_tokens.order(created_at: :desc)
    render json: { tokens: tokens.map { |t| serialize(t) } }
  end

  # POST /profile/personal_access_tokens
  # Body: { token: { name: "CI", scopes: "read", expires_at: "2027-01-01" } }
  def create
    pat, raw = PersonalAccessToken.generate_for(
      current_user,
      name:       token_params[:name],
      scopes:     token_params[:scopes].presence || "read",
      expires_at: token_params[:expires_at].present? ? Time.zone.parse(token_params[:expires_at]) : nil,
    )

    AuditLog.record(
      action:       "pat_created",
      auditable:    pat,
      changes_data: { name: pat.name, scopes: pat.scopes },
    )

    render json: {
      success:   true,
      token:     serialize(pat).merge(raw_token: raw),
      message:   "Token created. Copy it now — it will not be shown again.",
    }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { success: false, errors: e.record.errors.full_messages },
           status: :unprocessable_entity
  end

  # DELETE /profile/personal_access_tokens/:id
  def destroy
    pat = current_user.personal_access_tokens.find(params[:id])
    pat.revoke!

    AuditLog.record(
      action:       "pat_revoked",
      auditable:    pat,
      changes_data: { name: pat.name },
    )

    render json: { success: true, message: "Token revoked." }
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Token not found." }, status: :not_found
  end

  private

  def token_params
    params.require(:token).permit(:name, :scopes, :expires_at)
  end

  def serialize(pat)
    {
      id:           pat.id,
      name:         pat.name,
      scopes:       pat.scopes,
      last_four:    pat.last_four,
      last_used_at: pat.last_used_at&.iso8601,
      expires_at:   pat.expires_at&.iso8601,
      active:       pat.active,
      created_at:   pat.created_at.iso8601,
    }
  end
end
