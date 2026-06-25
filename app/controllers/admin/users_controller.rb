# Admin controller for managing DAM user accounts.
#
# == Tabs served by this controller
#
# | Tab           | Endpoint(s) |
# |---------------|-------------|
# | Properties    | GET/PATCH /admin/users/:id |
# | Groups        | GET /admin/users/:id/groups |
# | Permissions   | Delegated to FolderPoliciesController |
# | Impersonators | GET/POST/DELETE /admin/users/:id/impersonators |
# | Preferences   | GET/PATCH /admin/users/:id/preferences |
#
# == SSO protection
#
# For SSO-managed accounts, email/first_name/last_name are read-only because
# they are owned by Keycloak.  Only department, role, and group assignments
# can be changed.
class Admin::UsersController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_admin!
  before_action :set_target_user, only: [:show, :update, :destroy, :toggle_status,
                                         :groups, :change_password,
                                         :impersonators, :add_impersonator, :remove_impersonator,
                                         :preferences, :update_preferences]

  # GET /admin/users(.json)
  def index
    @active_view = 'Users'
    respond_to do |format|
      format.html
      format.json do
        scope = User.includes(:user_groups, :preference)

        # Full-text search across name, email, username, department
        if params[:search].present?
          q = "%#{params[:search].downcase}%"
          scope = scope.where(
            "lower(email) LIKE :q OR lower(first_name) LIKE :q OR lower(last_name) LIKE :q " \
            "OR lower(name) LIKE :q OR lower(COALESCE(username,'')) LIKE :q " \
            "OR lower(COALESCE(department,'')) LIKE :q",
            q: q
          )
        end

        users = scope.order(:email).limit(200).map { |u| serialize_user(u) }
        render json: { users: users }
      end
    end
  end

  # GET /admin/users/:id.json
  def show
    render json: { user: serialize_user(@target_user, detailed: true) }
  end

  # POST /admin/users
  def create
    @user = User.new(user_params)
    @user.name = "#{@user.first_name} #{@user.last_name}".strip

    temp_password = SecureRandom.base36(12)
    @user.password = temp_password
    @user.password_confirmation = temp_password
    @user.active = true
    @user.force_password_change = true

    if @user.save
      EmailOrchestrator.trigger(
        'user_created',
        @user.email,
        { 'user' => { 'first_name' => @user.first_name, 'temp_password' => temp_password } }
      )
      render json: { success: true, message: "User created successfully.", user: serialize_user(@user) }
    else
      render json: { success: false, errors: @user.errors.full_messages },
             status: :unprocessable_entity
    end
  end

  # PATCH /admin/users/:id
  def update
    # Prevent users from modifying their own admin status
    if @target_user == current_user && params[:user][:admin].present?
      return render json: { success: false, errors: ["You cannot change your own admin status"] },
                    status: :forbidden
    end

    # Prevent non-admins from elevating admin status
    if params[:user][:admin].present? && !current_user.admin?
      return render json: { success: false, errors: ["Unauthorized to modify admin status"] },
                    status: :forbidden
    end

    safe = @target_user.sso_managed? ? user_params.except(:email, :first_name, :last_name) : user_params

    if @target_user.update(safe)
      render json: { success: true, message: "User profile updated.", user: serialize_user(@target_user) }
    else
      render json: { success: false, errors: @target_user.errors.full_messages },
             status: :unprocessable_entity
    end
  end

  # DELETE /admin/users/:id  (soft-delete / deactivate)
  def destroy
    if @target_user == current_user
      return render json: { error: "You cannot delete your own account." }, status: :forbidden
    end
    @target_user.deactivate!
    render json: { success: true, message: "User account deactivated." }
  end

  # POST /admin/users/:id/toggle_status
  def toggle_status
    if @target_user.active?
      @target_user.deactivate!
      msg = "User access suspended."
    else
      @target_user.reactivate!
      msg = "User access restored."
    end
    render json: { success: true, message: msg, active: @target_user.active }
  end

  # POST /admin/users/:id/change_password
  def change_password
    if @target_user.sso_managed?
      return render json: { error: "Password is managed by your SSO provider." },
                    status: :unprocessable_entity
    end

    if @target_user.update(
      password: params[:new_password],
      password_confirmation: params[:new_password_confirmation],
      force_password_change: params[:force_change].present? ? params[:force_change] : false
    )
      render json: { success: true, message: "Password updated." }
    else
      render json: { success: false, errors: @target_user.errors.full_messages },
             status: :unprocessable_entity
    end
  end

  # GET /admin/users/:id/groups.json
  def groups
    render json: {
      groups: @target_user.user_groups.map { |g|
        { id: g.id, name: g.name, slug: g.slug, is_system: g.is_system }
      }
    }
  end

  # GET /admin/users/:id/impersonators.json
  def impersonators
    render json: {
      impersonators: @target_user.impersonators.map { |u|
        { id: u.id, display_name: u.display_name, email: u.email }
      }
    }
  end

  # POST /admin/users/:id/impersonators
  # Body: { impersonator_id: 42 }
  def add_impersonator
    actor = User.find_by(id: params[:impersonator_id])
    return render json: { error: "User not found." }, status: :not_found unless actor

    @target_user.grant_impersonation_to(actor)
    AuditLog.record(
      action:         'impersonation_grant',
      auditable:      @target_user,
      user:           current_user,
      changes_data:   { granted_to: actor.email }
    ) if defined?(AuditLog)

    render json: { success: true, message: "#{actor.display_name} can now impersonate #{@target_user.display_name}." }
  rescue ActiveRecord::RecordInvalid => e
    render json: { success: false, errors: [e.message] }, status: :unprocessable_entity
  end

  # DELETE /admin/users/:id/impersonators/:impersonator_id
  def remove_impersonator
    actor = User.find_by(id: params[:impersonator_id])
    @target_user.revoke_impersonation_from(actor) if actor

    AuditLog.record(
      action:       'impersonation_revoke',
      auditable:    @target_user,
      user:         current_user,
      changes_data: { revoked_from: actor&.email }
    ) if defined?(AuditLog)

    render json: { success: true, message: "Impersonation access revoked." }
  end

  # GET /admin/users/:id/preferences.json
  def preferences
    pref = @target_user.preference!
    render json: { preferences: serialize_preference(pref) }
  end

  # PATCH /admin/users/:id/preferences
  def update_preferences
    pref = @target_user.preference!
    if pref.update(preference_params)
      render json: { success: true, preferences: serialize_preference(pref) }
    else
      render json: { success: false, errors: pref.errors.full_messages },
             status: :unprocessable_entity
    end
  end

  private

  def set_target_user
    @target_user = User.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: "User not found." }, status: :not_found
  end

  def user_params
    params.require(:user).permit(:email, :first_name, :last_name, :department,
                                 :role, :admin, :avatar_url, user_group_ids: [])
  end

  def preference_params
    params.require(:preferences).permit(:language, :receive_mention_emails,
                                        :receive_workflow_emails)
  end

  def serialize_user(user, detailed: false)
    data = {
      id:           user.id,
      email:        user.email,
      display_name: user.display_name,
      first_name:   user.first_name,
      last_name:    user.last_name,
      username:     user.username,
      department:   user.department,
      role:         user.role,
      avatar_url:   user.avatar_url,
      sso_managed:  user.sso_managed?,
      admin:        user.admin,
      provider:     user.provider,
      active:       user.active,
      created_at:   user.created_at.strftime("%Y-%m-%d"),
      groups:       user.user_groups.pluck(:name),
      group_ids:    user.user_groups.pluck(:id)
    }

    if detailed
      data[:impersonators] = user.impersonators.map do |u|
        { id: u.id, display_name: u.display_name, email: u.email }
      end
      pref = user.preference
      data[:preferences] = pref ? serialize_preference(pref) : {}
    end

    data
  end

  def serialize_preference(pref)
    {
      language:                pref.language,
      receive_mention_emails:  pref.receive_mention_emails,
      receive_workflow_emails: pref.receive_workflow_emails
    }
  end

  def ensure_admin!
    unless current_user.admin? || current_user.super_admin?
      render json: { error: "Unauthorized" }, status: :forbidden
    end
  end
end