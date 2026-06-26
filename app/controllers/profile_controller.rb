# Self-service user profile controller.
#
# Handles the +/profile+ page where authenticated users can manage their own:
#
# * Personal details (name, department, avatar)
# * Preferences (theme, language, timezone, notification settings)
# * Password (local accounts only)
# * Recent activity (read-only audit log)
#
# The HTML shell mounts the React ProfilePage component via the Registry.
class ProfileController < ApplicationController
  before_action :authenticate_user!

  # GET /profile
  def show
    @preference = current_user.preference!
    @audit_logs = AuditLog
      .where(user_id: current_user.id)
      .order(created_at: :desc)
      .limit(50)
      .map { |log| serialize_log(log) }
      .to_json
  end

  # PATCH /profile
  def update
    safe_params = profile_params

    # SSO-managed users cannot change name / email
    if current_user.sso_managed?
      safe_params = safe_params.except(:first_name, :last_name, :email)
    end

    if current_user.update(safe_params)
      render json: { success: true, message: "Profile updated.", user: serialize_user }
    else
      render json: { success: false, errors: current_user.errors.full_messages },
             status: :unprocessable_entity
    end
  end

  # PATCH /profile/password
  def update_password
    if current_user.sso_managed?
      return render json: { error: "Password is managed by your SSO provider." },
                    status: :unprocessable_entity
    end

    unless current_user.valid_password?(params[:current_password])
      return render json: { success: false, errors: [ "Current password is incorrect." ] },
                    status: :unprocessable_entity
    end

    if current_user.update(
      password:              params[:new_password],
      password_confirmation: params[:new_password_confirmation],
    )
      # Keep the user signed in after a password change (Devise 5+)
      bypass_sign_in(current_user)
      render json: { success: true, message: "Password updated." }
    else
      render json: { success: false, errors: current_user.errors.full_messages },
             status: :unprocessable_entity
    end
  end

  # PATCH /profile/preferences
  def update_preferences
    pref = current_user.preference!
    if pref.update(preference_params)
      render json: { success: true, preferences: serialize_preference(pref) }
    else
      render json: { success: false, errors: pref.errors.full_messages },
             status: :unprocessable_entity
    end
  end

  # GET /profile/activity.json
  #
  # Returns paginated activity entries for the "My Activity" tab.
  def activity
    logs = AuditLog
      .where(user_id: current_user.id)
      .order(created_at: :desc)
      .limit(params.fetch(:limit, 50).to_i)
      .offset(params.fetch(:offset, 0).to_i)

    render json: {
      total:    AuditLog.where(user_id: current_user.id).count,
      activity: logs.map { |l| serialize_log(l) },
    }
  end

  private

  def profile_params
    params.require(:user).permit(:first_name, :last_name, :email, :department, :avatar_url)
  end

  def preference_params
    params.require(:preferences).permit(:language, :theme, :timezone,
                                        :receive_mention_emails, :receive_workflow_emails)
  end

  def serialize_user
    u = current_user
    {
      id:          u.id,
      email:       u.email,
      display_name: u.display_name,
      first_name:  u.first_name,
      last_name:   u.last_name,
      department:  u.department,
      avatar_url:  u.avatar_url,
      sso_managed: u.sso_managed?,
      admin:       u.admin,
      role:        u.role,
    }
  end

  def serialize_preference(pref)
    {
      language:               pref.language,
      theme:                  pref.theme,
      timezone:               pref.timezone,
      receive_mention_emails:  pref.receive_mention_emails,
      receive_workflow_emails: pref.receive_workflow_emails,
    }
  end

  def serialize_log(log)
    {
      id:             log.id,
      action:         log.action,
      auditable_type: log.auditable_type,
      auditable_id:   log.auditable_id,
      impersonated:   log.impersonated,
      true_user_id:   log.true_user_id,
      ip_address:     log.ip_address,
      created_at:     log.created_at.iso8601,
    }
  end
end
