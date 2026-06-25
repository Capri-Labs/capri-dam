class Admin::FolderPoliciesController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_admin!
  before_action :set_folder

  # GET /admin/folders/:folder_id/folder_policies
  def index
    # 1. Fetch Explicit Policies (Rules applied directly to this folder)
    explicit_policies = @folder.folder_policies.includes(:user_group).map do |policy|
      format_policy(policy, inherited: false)
    end

    # 2. Fetch Inherited Policies (Rules applied to parent folders)
    # Assuming Folder has a `parent_id` or ancestry setup. We traverse up:
    inherited_policies = []
    current_parent = @folder.parent # Adjust based on your Folder model's self-join logic

    while current_parent
      current_parent.folder_policies.includes(:user_group).each do |policy|
        # Only add it if an explicit rule for this group doesn't already exist here
        unless explicit_policies.any? { |ep| ep[:group_id] == policy.user_group_id }
          inherited_policies << format_policy(policy, inherited: true, source_folder: current_parent.name)
        end
      end
      current_parent = current_parent.parent
    end

    render json: {
      folder_name: @folder.name,
      explicit_policies: explicit_policies,
      inherited_policies: inherited_policies
    }
  end

  # POST /admin/folders/:folder_id/folder_policies
  # Updates or creates a permission matrix for a specific group on this folder
  def create
    policy = FolderPolicy.find_or_initialize_by(
      folder_id: @folder.id,
      user_group_id: params[:group_id]
    )

    if policy.update(policy_params)
      render json: { success: true, policy: format_policy(policy, inherited: false) }
    else
      render json: { success: false, errors: policy.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /admin/folders/:folder_id/folder_policies/:group_id
  # Removes the explicit rule, falling back to whatever is inherited
  def destroy
    policy = @folder.folder_policies.find_by(user_group_id: params[:group_id])
    policy&.destroy

    render json: { success: true, message: "Folder policy removed." }
  end

  private

  def set_folder
    # Uses UUID from params as established in the migration
    @folder = Folder.find(params[:folder_id])
  end

  def policy_params
    params.require(:policy).permit(
      :read_access, :modify_access, :create_access, :delete_access,
      :replicate_access, :manage_access, :explicit_deny
    )
  end

  def format_policy(policy, inherited:, source_folder: nil)
    {
      id:            policy.id,
      group_id:      policy.user_group_id,
      group_name:    policy.user_group.name,
      inherited:     inherited,
      source_folder: source_folder,
      matrix: {
        read:      policy.read_access,
        modify:    policy.modify_access,
        create:    policy.create_access,
        delete:    policy.delete_access,
        replicate: policy.replicate_access,
        manage:    policy.manage_access,
        explicit_deny: policy.explicit_deny
      }
    }
  end

  def ensure_admin!
    render json: { error: "Unauthorized" }, status: :forbidden unless current_user.admin?
  end
end