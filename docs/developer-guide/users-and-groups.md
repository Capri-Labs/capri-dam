# Users & User Groups

## Overview

The DAM uses a **group-based permission model** built on a closure-table hierarchy.  
Users belong to one or more groups; groups can be nested inside other groups.  
Permissions are expressed as **ACL entries** (`FolderPolicy`) that link a group to a folder with a granular permission matrix.

---

## Authentication

Two identity providers are supported simultaneously:

| Mode | Description |
|------|-------------|
| **Local** | Email + password stored in the DAM database. |
| **Keycloak SSO** | Federated via OmniAuth `keycloak_openid`. Orgs connect their own IdP inside Keycloak. |

On every SSO login the `User.from_omniauth` class method **syncs** mutable profile fields (name, first/last name, avatar) from the Keycloak token.  
Email and UID are immutable after initial provisioning to preserve referential integrity.

---

## Built-in System Groups

Four groups are seeded automatically and are **protected** — they cannot be deleted by anyone, including super-admins:

| Group | Slug | Notes |
|-------|------|-------|
| **everyone** | `everyone` | Every user is an implicit member. Grants default permissions. Do not delete. |
| **administrators** | `administrators` | Full access to all content. Bypasses explicit-deny rules. Only super-admins can modify membership. |
| **super-administrators** | `super-administrators` | Strictest operations. Reserved for future super-admin-only configs. |
| **metadata_users** | `metadata_users` | Gates write access (create/duplicate/edit/delete) to Metadata Schemas (`Tools › Metadata Schemas`). Non-members get read-only access. Membership is editable by admins/super-admins like any other group; the group itself (slug/is_system) is immutable. See `User#metadata_schema_manager?`. |

Model-level `validate` callbacks enforce slug/is_system immutability.  
`before_destroy` prevents deletion of any system group.

---

## ACL Permission Matrix

`FolderPolicy` links a `UserGroup` to a `Folder` with these boolean flags:

| Column | UI Label | What it grants |
|--------|----------|----------------|
| `read_access` | Read | View assets and child folders |
| `modify_access` | Modify | Edit existing asset metadata / rename folders |
| `create_access` | Create | Upload assets / create sub-folders |
| `delete_access` | Delete | Delete assets and folders |
| `replicate_access` | Replicate | Push assets to CDN |
| `manage_access` | Manage | Admin-level folder configuration |
| `explicit_deny` | — | Short-circuits ALL permissions for the group on this folder |

### Aggregation algorithm (`User#permissions_for`)

1. **Admins / administrators group** — always full access, even if a `deny-everyone` policy exists.
2. **Any `explicit_deny`** in an inherited group chain — all permissions denied.
3. Otherwise permissions are **OR-aggregated** across all applicable policies.

### Inheritance

Policies on a parent folder are **inherited** by child folders unless overridden by an explicit policy on the child. The REST API returns both `explicit_policies` and `inherited_policies`.

---

## User Impersonation

An admin can grant user-B the ability to impersonate user-A:

- All actions by user-B appear in the audit log as if performed by user-A.
- An explicit audit entry is written at impersonation **start** and **end** so security reviews can identify the impersonation window.
- Self-impersonation is prevented at the model level.

### API

```
GET    /admin/users/:id/impersonators           # List who can impersonate this user
POST   /admin/users/:id/add_impersonator        # Grant impersonation access
DELETE /admin/users/:id/impersonators/:imp_id   # Revoke impersonation access
```

---

## User Tabs

Every user detail overlay exposes these tabs:

| Tab | Description |
|-----|-------------|
| **Properties** | Email, name, department, role, SSO status |
| **Groups** | Groups the user belongs to |
| **Permissions** | Effective ACL per folder (delegated to FolderPoliciesController) |
| **Impersonators** | Accounts allowed to act as this user |
| **Preferences** | Language and notification preferences |

## Group Tabs

Every group overlay exposes:

| Tab | Description |
|-----|-------------|
| **Properties** | Name, description, slug |
| **Members** | Direct user members + sub-groups |
| **Permissions** | ACL matrix for all folders where this group has an entry |

---

## Group Hierarchy UI — Pagination & Bulk Delete

`/admin/user_groups` (`UserGroupsManager.jsx`) fetches the **full** group list in
one request (`GET /admin/user_groups.json`) and paginates **client-side**:

- Only **root-level custom groups** (no `parent_id`) are paginated, 10 per
  page (`ROOT_GROUPS_PER_PAGE`). A root group's descendants always render on
  the same page as their parent, so the tree never splits a group from its
  children across pages.
- System groups (`everyone`, `administrators`, `super-administrators`) are
  shown in a separate, unpaginated section above the custom-groups tree.
- Pagination controls ("Previous" / "Page X of Y" / "Next") only render when
  there is more than one page, and reuse the shared `common.previous`,
  `common.pageOf`, and `common.next` i18n keys (same convention as
  `MetadataSchemasManager`).
- Typing in the search box shows a flat, unpaginated list of matches instead
  of the tree, and resets pagination to page 1.
- Bulk-select/bulk-delete (`DELETE /admin/user_groups/bulk_delete`) only
  operates on root-level custom groups visible on the **current page**;
  system groups are always excluded server-side even if their ids are passed.

---

## GraphQL API

New queries and mutations are available at `/graphql`:

### Queries (admin only)
```graphql
users { id email displayName groups { name } impersonators { email } preferences { language } }
user(id: ID!) { ... }
userGroups { id name slug isSystem deletable members { email } }
userGroup(id: ID!) { ... }
```

### Mutations (admin only)
```graphql
createUser(email: email! firstName: String! lastName: String! ...) { user errors }
updateUser(id: ID! ...) { user errors }
createUserGroup(name: String! description: String parentId: ID) { userGroup errors }
updateUserGroup(id: ID! name: String description: String) { userGroup errors }
deleteUserGroup(id: ID!) { success errors }
```

---

## Database Tables

| Table | Purpose |
|-------|---------|
| `users` | Devise + OmniAuth user accounts |
| `user_groups` | Hierarchical groups (+ `is_system`, `slug`, `parent_id`) |
| `user_group_memberships` | Many-to-many users ↔ groups |
| `user_group_closures` | Closure table for O(1) ancestor lookups |
| `folder_policies` | ACL entries (group, folder, permission flags) |
| `user_impersonators` | Who is allowed to impersonate whom |
| `user_preferences` | Language + notification settings per user |

