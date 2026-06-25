# Admin controller for managing user groups.
#
# == System group protection
#
# Built-in groups (everyone, administrators, super-administrators) are protected
# at the model level:
# * +everyone+ — completely immutable; description-only edits are rejected.
# * +administrators+ and +super-administrators+ — only super-admins can modify
#   membership; no one can delete them.
#
# == API shape
#
# All endpoints accept and return JSON.  The HTML +index+ action renders the
# React shell that mounts the full overlay-based group management UI.
class Admin::UserGroupsController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_admin!
  before_action :set_group, only: [:show, :update, :destroy, :add_member, :remove_member,
                                   :add_group_member, :remove_group_member]

  # GET /admin/user_groups(.json)
  def index
    respond_to do |format|
      format.html { @active_view = 'User Groups' }
      format.json do
        groups = UserGroup.includes(:users, :child_groups).map do |group|
          parent_closure = UserGroupClosure.find_by(descendant_id: group.id, distance: 1)
          serialize_group(group, parent_id: parent_closure&.ancestor_id)
        end
        render json: { user_groups: groups }
      end
    end
  end

  # GET /admin/user_groups/:id.json
  def show
    parent_closure = UserGroupClosure.find_by(descendant_id: @group.id, distance: 1)
    render json: {
      group: serialize_group(@group, parent_id: parent_closure&.ancestor_id, include_members: true)
    }
  end

  # POST /admin/user_groups
  def create
    @group = UserGroup.new(group_params)

    if @group.save
      if params[:parent_id].present?
        parent = UserGroup.find_by(id: params[:parent_id])
        parent&.add_child(@group)
      end
      render json: { success: true, group: serialize_group(@group) }, status: :created
    else
      render json: { success: false, errors: @group.errors.full_messages },
             status: :unprocessable_entity
    end
  end

  # PATCH /admin/user_groups/:id
  def update
    # Only super-admins can edit the administrators group
    if @group.administrators? && !current_user.super_admin?
      return render json: { error: "Only super-administrators can modify this group." },
                    status: :forbidden
    end

    # No one can modify the slug or is_system flag of a system group
    safe = group_params
    safe = safe.except(:slug, :is_system) if @group.system?

    if @group.update(safe)
      render json: { success: true, group: serialize_group(@group) }
    else
      render json: { success: false, errors: @group.errors.full_messages },
             status: :unprocessable_entity
    end
  end

  # DELETE /admin/user_groups/:id
  def destroy
    if @group.system?
      return render json: { error: "System group '#{@group.name}' cannot be deleted." },
                    status: :forbidden
    end

    @group.destroy
    render json: { success: true, message: "Group deleted." }
  end

  # POST /admin/user_groups/:id/add_member
  # Adds a user to the group.  Body: { email: "..." } or { user_id: 42 }
  def add_member
    if @group.everyone?
      return render json: { error: "Members are managed automatically for the 'everyone' group." },
                    status: :forbidden
    end

    # super-administrators group: only super-admins can add members
    if @group.super_administrators? && !current_user.super_admin?
      return render json: { error: "Only super-administrators can modify the super-administrators group." },
                    status: :forbidden
    end

    # administrators group: admins and super-admins can add — but not super-admin-only check above
    # (No extra restriction needed here — any admin can add to administrators)

    user = params[:email].present? ? User.find_by(email: params[:email]) :
                                     User.find_by(id: params[:user_id])

    unless user
      return render json: { error: "User not found." }, status: :not_found
    end

    # Block self-promotion: user cannot add themselves to admin/super-admin groups
    if user == current_user && (@group.administrators? || @group.super_administrators?)
      return render json: { error: "You cannot add yourself to the #{@group.name} group." },
                    status: :forbidden
    end

    unless @group.users.include?(user)
      @group.users << user
    end

    render json: { success: true, message: "#{user.display_name} added to #{@group.name}." }
  end

  # DELETE /admin/user_groups/:id/remove_member
  # Body: { user_id: 42 }
  def remove_member
    if @group.everyone?
      return render json: { error: "Cannot remove users from the 'everyone' group." },
                    status: :forbidden
    end
    if @group.administrators? && !current_user.super_admin?
      return render json: { error: "Only super-administrators can modify the administrators group." },
                    status: :forbidden
    end

    user = User.find_by(id: params[:user_id])
    @group.users.delete(user) if user
    render json: { success: true, message: "User removed from #{@group.name}." }
  end

  # POST /admin/user_groups/:id/add_group_member
  # Nests another group as a child of this group.  Body: { child_group_id: 42 }
  def add_group_member
    child = UserGroup.find_by(id: params[:child_group_id])
    return render json: { error: "Group not found." }, status: :not_found unless child
    return render json: { error: "Cannot nest a group inside itself." }, status: :unprocessable_entity if child.id == @group.id

    @group.add_child(child)
    render json: { success: true, message: "#{child.name} added as a sub-group of #{@group.name}." }
  end

  # DELETE /admin/user_groups/:id/remove_group_member
  def remove_group_member
    child = UserGroup.find_by(id: params[:child_group_id])
    render json: { success: true } and return unless child

    # Clear parent_id FK so the has_many :child_groups association stays in sync
    child.update_column(:parent_id, nil) if child.parent_id == @group.id

    UserGroupClosure.where(ancestor_id: @group.id, descendant_id: child.id).delete_all
    render json: { success: true, message: "#{child.name} removed from #{@group.name}." }
  end

  private

  def set_group
    @group = UserGroup.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Group not found." }, status: :not_found
  end

  def group_params
    params.require(:user_group).permit(:name, :description, :parent_id)
  end

  def serialize_group(group, parent_id: nil, include_members: false)
    data = {
      id:           group.id,
      name:         group.name,
      slug:         group.slug,
      description:  group.description,
      is_system:    group.is_system,
      parent_id:    parent_id || group.parent_id,
      member_count: group.users.count,
      created_at:   group.created_at
    }

    if include_members
      data[:members] = group.users.map do |u|
        { id: u.id, display_name: u.display_name, email: u.email, avatar_url: u.avatar_url }
      end

      # Use the closure table (distance: 1) as the authoritative source for direct children.
      # This handles legacy rows where parent_id was not backfilled yet.
      child_ids = UserGroupClosure.where(ancestor_id: group.id, distance: 1).pluck(:descendant_id)
      data[:child_groups] = UserGroup.where(id: child_ids).map do |cg|
        { id: cg.id, name: cg.name, slug: cg.slug, description: cg.description, is_system: cg.is_system }
      end
    end

    data
  end

  def ensure_admin!
    unless current_user.admin? || current_user.super_admin?
      render json: { error: "Unauthorized" }, status: :forbidden
    end
  end
end