# frozen_string_literal: true

# Mixin providing fine-grained authorization helpers for all controllers.
#
# == Permission hierarchy (highest → lowest)
#
# 1. Super-admin (member of `super-administrators` group)
# 2. Admin (user.admin? OR member of `administrators` group)
# 3. Regular user with folder-level grants (FolderPolicy)
# 4. Regular user with no grants — read-only or fully denied
#
# == PAT scope enforcement
#
# When authentication was via a Personal Access Token (PAT), additional
# scope checks are applied to prevent a read-only PAT from modifying data:
#
#   read  → GET-only endpoints
#   write → POST / PATCH / PUT
#   admin → admin-only operations (e.g. CDN flush, user management)
#
# @example Require admin role
#   before_action :require_admin!
#
# @example Require read access to a folder
#   before_action -> { check_folder_permission!(@folder, :read) }, only: %i[show]
#
# @example Require write access to a folder
#   before_action -> { check_folder_permission!(@folder, :create) }, only: %i[create]
module Authorization
  extend ActiveSupport::Concern

  included do
    helper_method :current_user_admin? if respond_to?(:helper_method)
  end

  # ---------------------------------------------------------------------------
  # Role-based guards
  # ---------------------------------------------------------------------------

  # Halts the request with 403 unless the current user is an admin
  # (user.admin? flag OR member of the administrators/super-administrators group).
  def require_admin!
    return if current_user_admin?

    render json: { error: "Administrator privileges required." }, status: :forbidden
  end

  # Halts the request with 403 unless the current user is a super-admin
  # (member of the super-administrators group only).
  def require_super_admin!
    return if current_user&.super_admin?

    render json: { error: "Super-administrator privileges required." }, status: :forbidden
  end

  # Convenience predicate — true for admin flag OR group membership.
  def current_user_admin?
    return false unless current_user

    current_user.admin? || current_user.member_of_administrators?
  end

  # ---------------------------------------------------------------------------
  # PAT scope guards
  # ---------------------------------------------------------------------------

  # Requires the request to carry write (or admin) scope when authenticated
  # via a Personal Access Token.  Devise sessions are implicitly trusted.
  #
  # Call this before any state-mutating action that PAT clients may reach.
  def require_write_scope!
    return unless pat_authenticated?

    unless pat_has_scope?(%w[write admin])
      render json: {
        error: "Insufficient token scope. A 'write' or 'admin' PAT is required for this operation.",
      }, status: :forbidden
    end
  end

  # Requires admin scope when authenticated via PAT.
  def require_admin_scope!
    return unless pat_authenticated?

    unless pat_has_scope?(%w[admin])
      render json: {
        error: "Insufficient token scope. An 'admin' PAT is required for this operation.",
      }, status: :forbidden
    end
  end

  # ---------------------------------------------------------------------------
  # Folder-level permission guards
  # ---------------------------------------------------------------------------

  # Checks that +current_user+ holds a specific folder permission.
  # Renders 403 if access is denied.
  #
  # Permission symbols map to {FolderPolicy} columns:
  #   :read, :modify, :create, :delete, :replicate, :manage
  #
  # @param folder [Folder, nil] if nil the check is skipped (root-level access)
  # @param permission [Symbol] the permission key to check
  def check_folder_permission!(folder, permission)
    return if folder_permission?(folder, permission)

    render json: {
      error: "Access denied. You do not have '#{permission}' permission for this folder.",
    }, status: :forbidden
  end

  # Non-halting predicate version of {#check_folder_permission!}. Useful for
  # bulk/batch operations (e.g. multi-item Move) that need to evaluate
  # permission per-item and collect failures instead of aborting the whole
  # request on the first denial.
  #
  # @param folder [Folder, nil] if nil the check always passes (root-level access)
  # @param permission [Symbol] the permission key to check
  # @return [Boolean]
  def folder_permission?(folder, permission)
    return true if folder.nil?          # root — no policy applicable
    return true if current_user_admin?  # admins bypass all folder policies

    !!(current_user&.permissions_for(folder) || {})[permission]
  end

  # Convenience wrapper — check :read on an asset's parent folder.
  # @param asset [Asset]
  def check_asset_read!(asset)
    return if current_user_admin?
    return unless asset.folder_id # root-level asset, no folder policy

    folder = Folder.find_by(id: asset.folder_id)
    check_folder_permission!(folder, :read)
  end

  # Convenience wrapper — check :modify on an asset's parent folder.
  # @param asset [Asset]
  def check_asset_modify!(asset)
    return if current_user_admin?
    return unless asset.folder_id

    folder = Folder.find_by(id: asset.folder_id)
    check_folder_permission!(folder, :modify)
  end

  # Convenience wrapper — check :delete on an asset's parent folder.
  # @param asset [Asset]
  def check_asset_delete!(asset)
    return if current_user_admin?
    return unless asset.folder_id

    folder = Folder.find_by(id: asset.folder_id)
    check_folder_permission!(folder, :delete)
  end

  private

  # Returns true when the current request was authenticated via a PAT
  # (detected by the `dat_` prefix on the raw Authorization header).
  def pat_authenticated?
    raw = request.headers["Authorization"]&.sub(/\ABearer\s+/, "")
    raw&.start_with?(PersonalAccessToken::PREFIX) || false
  end

  # Returns true when the PAT's stored scopes include any of +required+.
  # @param required [Array<String>]
  def pat_has_scope?(required)
    raw    = request.headers["Authorization"]&.sub(/\ABearer\s+/, "")
    return false unless raw&.start_with?(PersonalAccessToken::PREFIX)

    digest = Digest::SHA256.hexdigest(raw)
    pat    = PersonalAccessToken.active.unexpired.find_by(token_digest: digest)
    return false unless pat

    required.any? { |s| pat.scopes.to_s.split(",").map(&:strip).include?(s) }
  end
end
