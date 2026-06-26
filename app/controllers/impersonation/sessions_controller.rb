# Impersonation::SessionsController
#
# Manages the "act as" session that lets admins and super-admins log in as
# another user for troubleshooting purposes.
#
# == Security rules
#
# | Actor        | Can impersonate           |
# |--------------|---------------------------|
# | Super-admin  | Any user (incl. admins)   |
# | Admin        | Any non-super-admin user  |
# | Other users  | Only via explicit grants  |
#
# Super-admins are NEVER impersonatable to prevent privilege escalation.
#
# == Session mechanics
#
# * +session[:impersonated_user_id]+ — ID of the account being impersonated.
# * +session[:impersonator_id]+      — ID of the real admin (safety net).
# * No password is ever touched.
#
# == Audit trail
#
# Both session start and end write an explicit {AuditLog} row so security
# reviews can reconstruct the full impersonation window with timestamps.
class Impersonation::SessionsController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_can_impersonate!, only: :create

  # POST /impersonation/start/:user_id
  #
  # Starts an impersonation session.  Returns JSON so the React UI can update
  # the impersonation banner immediately.
  def create
    AuditLog.record(
      action:       "impersonation_start",
      auditable:    @target_user,
      user:         true_user,
      changes_data: {
        impersonated_user:  @target_user.email,
        impersonated_by:    true_user.email,
        ip:                 request.remote_ip,
      },
    )

    session[:impersonated_user_id] = @target_user.id
    session[:impersonator_id]      = true_user.id

    render json: {
      success:          true,
      message:          "You are now impersonating #{@target_user.display_name}.",
      impersonated_user: { id: @target_user.id, display_name: @target_user.display_name, email: @target_user.email },
    }
  end

  # DELETE /impersonation/stop
  #
  # Ends the impersonation session and redirects back to the admin dashboard.
  def destroy
    if (imp_id = session[:impersonated_user_id])
      impersonated = User.find_by(id: imp_id)

      AuditLog.record(
        action:       "impersonation_end",
        auditable:    impersonated || true_user,
        user:         true_user,
        changes_data: {
          impersonated_user: impersonated&.email,
          impersonated_by:   true_user.email,
          ip:                request.remote_ip,
        },
      )
    end

    session.delete(:impersonated_user_id)
    session.delete(:impersonator_id)

    respond_to do |format|
      format.json { render json: { success: true } }
      format.html { redirect_to "/admin/users", notice: "Impersonation session ended." }
    end
  end

  private

  def ensure_can_impersonate!
    @target_user = User.find_by(id: params[:user_id])

    unless @target_user
      return render json: { error: "User not found." }, status: :not_found
    end

    unless @target_user.can_be_impersonated_by?(true_user)
      render json: { error: "You are not authorised to impersonate this user." },
                    status: :forbidden
    end
  end
end
