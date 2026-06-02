class Admin::UserGroupsController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_admin!

  before_action :set_group, only: [:add_user, :remove_user]

  # GET /admin/user_groups
  def index
    @active_view = 'User Groups'
    respond_to do |format|
      # 1. When the browser hits the URL, load the ERB view (which mounts React)
      format.html

      # 2. When React fetches the data, return the JSON payload
      format.json do
        groups = UserGroup.all.map do |group|
          parent_closure = UserGroupClosure.find_by(descendant_id: group.id, distance: 1)

          {
            id: group.id,
            name: group.name,
            description: group.description,
            parent_id: parent_closure&.ancestor_id,
            member_count: group.users.count
          }
        end

        render json: { user_groups: groups }
      end
    end
  end

  # POST /admin/user_groups
  def create
    @group = UserGroup.new(group_params)

    if @group.save
      # If a parent ID was passed from the UI, establish the hierarchy
      if params[:parent_id].present?
        parent = UserGroup.find_by(id: params[:parent_id])
        parent.add_child(@group) if parent
      end

      render json: { success: true, group: @group }, status: :created
    else
      render json: { success: false, errors: @group.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # POST /admin/user_groups/:id/add_user
  def add_user
    user = User.find_by(email: params[:email])

    if user
      @group.users << user unless @group.users.include?(user)
      render json: { success: true, message: "User added successfully." }
    else
      render json: { success: false, error: "User not found." }, status: :not_found
    end
  end

  # DELETE /admin/user_groups/:id/remove_user
  def remove_user
    user = User.find_by(id: params[:user_id])
    @group.users.delete(user) if user
    render json: { success: true, message: "User removed successfully." }
  end

  private

  def set_group
    @group = UserGroup.find(params[:id])
  end

  def group_params
    params.require(:user_group).permit(:name, :description)
  end

  def ensure_admin!
    render json: { error: "Unauthorized" }, status: :forbidden unless current_user.admin?
  end
end