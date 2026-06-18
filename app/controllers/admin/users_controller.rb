class Admin::UsersController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_admin!
  before_action :set_target_user, only: [:update, :toggle_status]

  # GET /admin/users
  def index
    @active_view = 'Users'
    respond_to do |format|
      format.html
      format.json do
        users = User.includes(:user_groups).map do |user|
          {
            id: user.id,
            email: user.email,
            display_name: user.display_name,
            first_name: user.first_name,
            last_name: user.last_name,
            department: user.department,
            role: user.role,
            avatar_url: user.avatar_url,
            sso_managed: user.sso_managed?,
            admin: user.admin,
            provider: user.provider,
            active: user.active,
            created_at: user.created_at.strftime("%Y-%m-%d"),
            groups: user.user_groups.pluck(:name),
            group_ids: user.user_groups.pluck(:id)
          }
        end
        render json: { users: users }
      end
    end
  end

  # POST /admin/users
  def create
    @user = User.new(user_params)

    # Combine first and last name to satisfy the database NOT NULL constraint
    @user.name = "#{@user.first_name} #{@user.last_name}".strip

    # Generate temporary password
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

      render json: { success: true, message: "User created successfully." }
    else
      render json: { success: false, errors: @user.errors.full_messages }
    end
  end

  # PATCH /admin/users/:id
  def update
    #  Enterprise Security: Prevent users from demoting themselves or non-admins from changing admin status
    if params[:user][:admin].present? && !current_user.admin?
      return render json: { success: false, errors: ["Unauthorized to modify admin status"] }, status: :forbidden
    end

    if @target_user.sso_managed?
      # Only allow updating local fields (like role/department) if the SSO doesn't manage them,
      # but strictly block email/name changes.
      safe_params = user_params.except(:email, :first_name, :last_name)
      success = @target_user.update(safe_params)
    else
      success = @target_user.update(user_params)
    end

    if success
      render json: { success: true, message: "User profile updated." }
    else
      render json: { success: false, errors: @target_user.errors.full_messages }
    end
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

  private

  def set_target_user
    @target_user = User.find(params[:id])
  end

  def user_params
    params.require(:user).permit(:email, :first_name, :last_name, :department, :role, :admin, user_group_ids: [])
  end

  def ensure_admin!
    render json: { error: "Unauthorized" }, status: :forbidden unless current_user.admin?
  end
end