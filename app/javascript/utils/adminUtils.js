/**
 * Shared CSRF-aware fetch helper.
 */
export async function apiFetch(url, opts = {}) {
  const csrf = document.querySelector('[name="csrf-token"]')?.content;
  const method = opts.method || 'GET';
  const headers = {
    'Content-Type': 'application/json',
    ...(csrf ? { 'X-CSRF-Token': csrf } : {}),
    ...(opts.headers || {}),
  };
  const response = await fetch(url, { ...opts, method, headers });
  return response.json();
}

/** System group slugs */
export const SYSTEM_SLUGS = {
  EVERYONE:    'everyone',
  ADMINS:      'administrators',
  SUPER_ADMINS: 'super-administrators',
};

export function isSystemGroup(group) {
  return group?.is_system === true || Object.values(SYSTEM_SLUGS).includes(group?.slug);
}

/**
 * Resolves what the current DAM operator is allowed to do to a target group.
 *
 * Updated rules (v2):
 *  - 'everyone'          : no add/remove by anyone (auto-managed)
 *  - 'administrators'    : admins AND super-admins can add/remove members
 *                          (adding makes the target user an admin)
 *  - 'super-admins'      : ONLY super-admins can add/remove
 *  - custom groups       : any admin can manage
 *
 * Self-promotion:
 *  - A user can NEVER add themselves to 'administrators' or 'super-administrators'
 *    — enforced separately by passing currentUserId and targetUserId at call-site.
 */
export function groupPermissions(group, isAdmin, isSuperAdmin) {
  const system = isSystemGroup(group);
  const slug   = group?.slug;

  const canManageAdmins = isAdmin || isSuperAdmin;    // both admin and super-admin
  const canManageSuperAdmins = isSuperAdmin;           // only super-admin

  return {
    canDelete: !system,
    canEdit:   !system || isSuperAdmin,
    canAddMembers:
      slug !== SYSTEM_SLUGS.EVERYONE &&
      (slug !== SYSTEM_SLUGS.ADMINS      || canManageAdmins) &&
      (slug !== SYSTEM_SLUGS.SUPER_ADMINS || canManageSuperAdmins),
    canRemoveMembers:
      slug !== SYSTEM_SLUGS.EVERYONE &&
      (slug !== SYSTEM_SLUGS.ADMINS      || canManageAdmins) &&
      (slug !== SYSTEM_SLUGS.SUPER_ADMINS || canManageSuperAdmins),
    canAssignUser:
      slug !== SYSTEM_SLUGS.EVERYONE &&
      (slug !== SYSTEM_SLUGS.ADMINS      || canManageAdmins) &&
      (slug !== SYSTEM_SLUGS.SUPER_ADMINS || canManageSuperAdmins),
  };
}

/**
 * Returns true when current user would be self-promoting themselves.
 * Blocks adding yourself to the administrators or super-administrators group.
 */
export function isSelfPromotion(group, currentUserId, targetUserId) {
  if (currentUserId == null || targetUserId == null) return false;
  if (String(currentUserId) !== String(targetUserId)) return false;
  return group?.slug === SYSTEM_SLUGS.ADMINS || group?.slug === SYSTEM_SLUGS.SUPER_ADMINS;
}

export function formatDate(dateStr) {
  if (!dateStr) return '—';
  return new Date(dateStr).toLocaleDateString(undefined, {
    year: 'numeric', month: 'short', day: 'numeric',
  });
}



