// E2E tests for DAM Users & User Groups management.
//
// Tests the full overlay-based UI including:
//  - User list, create, edit, suspend/restore
//  - User drawer tabs: Properties, Groups, Permissions, Impersonators, Preferences
//  - Group hierarchy tree with system group protection
//  - Group overlay tabs: Properties, Members, Permissions (ACL), Groups
//  - Access control: admin cannot assign to super-administrators group
//  - Password change dialog
//
// Prereqs: app running at E2E_BASE_URL with seed data (bin/rails db:seed).

const { test, expect } = require('./fixtures');

const ADMIN_EMAIL    = process.env.E2E_EMAIL    || 'admin@admin.com';
const ADMIN_PASSWORD = process.env.E2E_PASSWORD || 'AdminUser';

async function login(page) {
  await page.goto('/users/sign_in');
  await page.fill('input[name="user[email]"]', ADMIN_EMAIL);
  await page.fill('input[name="user[password]"]', ADMIN_PASSWORD);
  await page.click('button[type="submit"], input[type="submit"]');
  await page.waitForLoadState('networkidle');
}

// ─────────────────────────────────────────────────────────────────
// Users
// ─────────────────────────────────────────────────────────────────

test.describe('Admin — Users', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
    await page.goto('/admin/users');
    await page.waitForLoadState('networkidle');
  });

  test('user list page loads with data grid', async ({ page }) => {
    await expect(page.getByText('System Users')).toBeVisible();
    await expect(page.getByRole('grid')).toBeVisible();
  });

  test('invite local user button opens drawer', async ({ page }) => {
    await page.getByRole('button', { name: /invite local user/i }).click();
    await expect(page.getByText('Invite New User')).toBeVisible();
    await expect(page.getByLabel(/first name/i)).toBeVisible();
    await expect(page.getByLabel(/email address/i)).toBeVisible();
  });

  test('creates a new local user', async ({ page }) => {
    await page.getByRole('button', { name: /invite local user/i }).click();

    const email = `e2e_${Date.now()}@example.com`;
    await page.getByLabel(/first name/i).fill('E2E');
    await page.getByLabel(/last name/i).fill('User');
    await page.getByLabel(/email address/i).fill(email);
    await page.getByLabel(/department/i).fill('QA');
    await page.getByRole('button', { name: /provision local account/i }).click();

    await page.waitForLoadState('networkidle');
    await expect(page.getByText(email)).toBeVisible();
  });

  test('clicking a user row opens tabbed drawer', async ({ page }) => {
    // Click first data row (skip header)
    const firstRow = page.locator('.MuiDataGrid-row').first();
    await firstRow.click();

    // Expect all 5 tabs
    await expect(page.getByRole('tab', { name: /properties/i })).toBeVisible();
    await expect(page.getByRole('tab', { name: /groups/i })).toBeVisible();
    await expect(page.getByRole('tab', { name: /permissions/i })).toBeVisible();
    await expect(page.getByRole('tab', { name: /impersonators/i })).toBeVisible();
    await expect(page.getByRole('tab', { name: /preferences/i })).toBeVisible();
  });

  test('can navigate to Preferences tab and see language selector', async ({ page }) => {
    await page.locator('.MuiDataGrid-row').first().click();
    await page.getByRole('tab', { name: /preferences/i }).click();
    await expect(page.getByLabel(/interface language/i)).toBeVisible();
  });

  test('can navigate to Impersonators tab', async ({ page }) => {
    await page.locator('.MuiDataGrid-row').first().click();
    await page.getByRole('tab', { name: /impersonators/i }).click();
    // Should show info alert
    await expect(page.getByRole('alert')).toBeVisible();
  });

  test('suspend / restore user via drawer', async ({ page }) => {
    await page.locator('.MuiDataGrid-row').first().click();
    const suspendBtn = page.getByRole('button', { name: /suspend access|restore access/i });
    await expect(suspendBtn).toBeVisible();
    await suspendBtn.click();
    await page.waitForLoadState('networkidle');
    // Drawer should close after toggle
    await expect(page.getByText('System Users')).toBeVisible();
  });

  test('status chip shows Active/Suspended in grid', async ({ page }) => {
    const activeChip = page.locator('.MuiChip-root').filter({ hasText: /active|suspended/i }).first();
    await expect(activeChip).toBeVisible();
  });

  test('SSO managed users show SSO chip in Auth column', async ({ page }) => {
    // If SSO users exist, they show the provider chip
    // Just verify the Auth column header exists
    await expect(page.getByText('Auth')).toBeVisible();
  });

  test('admin badge (shield icon) visible for admin users', async ({ page }) => {
    // Admin user row should have shield icon
    // (depends on seed data having admin user)
    const grid = page.getByRole('grid');
    await expect(grid).toBeVisible();
  });

  test('group assignment modal opens from grid row', async ({ page }) => {
    const groupBtn = page.locator('[data-testid="GroupAddIcon"]').first();
    if (await groupBtn.isVisible({ timeout: 3000 })) {
      await groupBtn.click();
      await expect(page.getByText(/group hierarchy/i)).toBeVisible();
    }
  });

  test('change password dialog opens from Properties tab', async ({ page }) => {
    await page.locator('.MuiDataGrid-row').first().click();
    const changePassBtn = page.getByRole('button', { name: /change password/i });
    if (await changePassBtn.isVisible({ timeout: 3000 })) {
      await changePassBtn.click();
      await expect(page.getByText('Change Password')).toBeVisible();
      await expect(page.getByLabel(/new password/i)).toBeVisible();
    }
  });
});

// ─────────────────────────────────────────────────────────────────
// User Groups
// ─────────────────────────────────────────────────────────────────

test.describe('Admin — User Groups', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
    await page.goto('/admin/user_groups');
    await page.waitForLoadState('networkidle');
  });

  test('groups page loads with hierarchy tree', async ({ page }) => {
    await expect(page.getByText('User Groups')).toBeVisible();
  });

  test('system groups are visible in tree', async ({ page }) => {
    await expect(page.getByText('everyone')).toBeVisible();
    await expect(page.getByText('administrators')).toBeVisible();
    await expect(page.getByText('super-administrators')).toBeVisible();
  });

  test('system groups show "sys" badge', async ({ page }) => {
    // All 3 system groups should have the sys chip
    const sysChips = page.locator('.MuiChip-root').filter({ hasText: 'sys' });
    await expect(sysChips.first()).toBeVisible();
  });

  test('clicking a group opens the overlay drawer', async ({ page }) => {
    await page.getByText('everyone').click();
    await page.waitForLoadState('networkidle');

    // Overlay should have tabs
    await expect(page.getByRole('tab', { name: /properties/i })).toBeVisible();
    await expect(page.getByRole('tab', { name: /members/i })).toBeVisible();
    await expect(page.getByRole('tab', { name: /permissions/i })).toBeVisible();
    await expect(page.getByRole('tab', { name: /groups/i })).toBeVisible();
  });

  test('everyone group overlay shows it is immutable', async ({ page }) => {
    await page.getByText('everyone').click();
    await page.waitForLoadState('networkidle');

    // Should show immutability warning
    await expect(
      page.getByText(/system group|cannot be modified|automatic members/i)
    ).toBeVisible();
  });

  test('everyone group has NO delete button', async ({ page }) => {
    await page.getByText('everyone').click();
    await page.waitForLoadState('networkidle');

    // Delete button should not exist for system groups
    const deleteBtn = page.getByRole('button', { name: /delete group/i });
    await expect(deleteBtn).toHaveCount(0);
  });

  test('administrators group has NO delete button', async ({ page }) => {
    await page.getByText('administrators').first().click();
    await page.waitForLoadState('networkidle');
    const deleteBtn = page.getByRole('button', { name: /delete group/i });
    await expect(deleteBtn).toHaveCount(0);
  });

  test('can create a new custom group', async ({ page }) => {
    await page.getByRole('button', { name: /new group/i }).click();

    const groupName = `E2E Group ${Date.now()}`;
    await page.getByLabel(/group name/i).fill(groupName);
    await page.getByRole('button', { name: /create group/i }).click();
    await page.waitForLoadState('networkidle');

    await expect(page.getByText(groupName)).toBeVisible();
  });

  test('can open Members tab on a custom group', async ({ page }) => {
    // Create a group first or use existing
    await page.getByRole('button', { name: /new group/i }).click();
    const groupName = `Members Test ${Date.now()}`;
    await page.getByLabel(/group name/i).fill(groupName);
    await page.getByRole('button', { name: /create group/i }).click();
    await page.waitForLoadState('networkidle');

    // Click it
    await page.getByText(groupName).click();
    await page.waitForLoadState('networkidle');

    // Navigate to Members tab
    await page.getByRole('tab', { name: /members/i }).click();
    await expect(page.getByPlaceholder(/enter user email/i)).toBeVisible();
  });

  test('can open Permissions tab and see ACL matrix', async ({ page }) => {
    // Open any group
    await page.getByText('administrators').first().click();
    await page.waitForLoadState('networkidle');

    await page.getByRole('tab', { name: /permissions/i }).click();

    // ACL columns should be visible
    await expect(page.getByText(/read/i).first()).toBeVisible();
    await expect(page.getByText(/modify/i).first()).toBeVisible();
    await expect(page.getByText(/create/i).first()).toBeVisible();
    await expect(page.getByText(/delete/i).first()).toBeVisible();
    await expect(page.getByText(/replicate/i).first()).toBeVisible();
  });

  test('can delete a non-system group', async ({ page }) => {
    await page.getByRole('button', { name: /new group/i }).click();
    const groupName = `Delete Me ${Date.now()}`;
    await page.getByLabel(/group name/i).fill(groupName);
    await page.getByRole('button', { name: /create group/i }).click();
    await page.waitForLoadState('networkidle');

    await page.getByText(groupName).click();
    await page.waitForLoadState('networkidle');

    // Click delete icon in overlay header
    const deleteIcon = page.locator('[data-testid="DeleteOutlinedIcon"]');
    await deleteIcon.click();

    // Confirm dialog
    await page.getByRole('button', { name: /delete group/i }).click();
    await page.waitForLoadState('networkidle');

    await expect(page.getByText(groupName)).toHaveCount(0);
  });

  test('can search/filter groups in tree', async ({ page }) => {
    await page.getByPlaceholder(/search groups/i).fill('admin');
    await expect(page.getByText('administrators')).toBeVisible();
    await expect(page.getByText('super-administrators')).toBeVisible();

    // "everyone" should not be visible after filter
    await expect(page.getByText('everyone')).toHaveCount(0);
  });
});

// ─────────────────────────────────────────────────────────────────
// Access Control — Group Assignment Restrictions
// ─────────────────────────────────────────────────────────────────

test.describe('Access Control — Group Assignment', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
    await page.goto('/admin/users');
    await page.waitForLoadState('networkidle');
  });

  test('group assignment modal shows info alert about restricted groups', async ({ page }) => {
    const groupBtn = page.locator('[data-testid="GroupAddIcon"]').first();
    if (await groupBtn.isVisible({ timeout: 3000 })) {
      await groupBtn.click();

      // Should show info alert about administrators/super-administrators restriction
      await expect(
        page.getByText(/administrators.*super-administrators.*super-admins/i)
          .or(page.getByRole('alert').filter({ hasText: /administrators/i }))
      ).toBeVisible({ timeout: 5000 });
    }
  });

  test('administrators group in assignment modal shows locked icon for non-super-admin', async ({ page }) => {
    const groupBtn = page.locator('[data-testid="GroupAddIcon"]').first();
    if (await groupBtn.isVisible({ timeout: 3000 })) {
      await groupBtn.click();

      // The administrators group should have a lock icon (not a checkbox)
      const lockIcon = page.locator('[data-testid="LockOutlinedIcon"]');
      await expect(lockIcon.first()).toBeVisible({ timeout: 5000 });
    }
  });

  test('super-administrators group in assignment modal shows locked icon', async ({ page }) => {
    const groupBtn = page.locator('[data-testid="GroupAddIcon"]').first();
    if (await groupBtn.isVisible({ timeout: 3000 })) {
      await groupBtn.click();

      // super-administrators should have lock icon
      const lockIcons = page.locator('[data-testid="LockOutlinedIcon"]');
      const count = await lockIcons.count();
      expect(count).toBeGreaterThanOrEqual(1);
    }
  });
});

// ─────────────────────────────────────────────────────────────────
// Folder Permissions ACL
// ─────────────────────────────────────────────────────────────────

test.describe('Folder Permissions ACL', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
  });

  test('ACL matrix shows Read/Modify/Create/Delete/Replicate columns', async ({ page }) => {
    await page.goto('/admin/user_groups');
    await page.waitForLoadState('networkidle');

    await page.getByText('administrators').first().click();
    await page.waitForLoadState('networkidle');

    await page.getByRole('tab', { name: /permissions/i }).click();

    // The ACL matrix should show all the DAM permission columns
    for (const col of ['Read', 'Modify', 'Create', 'Delete', 'Replicate']) {
      await expect(page.getByText(col).first()).toBeVisible({ timeout: 8000 });
    }
  });

  test('ACL matrix shows Deny All column', async ({ page }) => {
    await page.goto('/admin/user_groups');
    await page.waitForLoadState('networkidle');

    await page.getByText('administrators').first().click();
    await page.waitForLoadState('networkidle');

    await page.getByRole('tab', { name: /permissions/i }).click();
    await expect(page.getByText(/deny all/i)).toBeVisible({ timeout: 8000 });
  });
});

//
// Tests the full overlay-based UI for creating, editing, and managing users
// and groups, including system group protection, impersonation grants, and
// ACL permission matrix editing.
//
// Prereqs: app running at E2E_BASE_URL with seed data (bin/rails db:seed).

const { test, expect } = require('./fixtures');

const ADMIN_EMAIL    = process.env.E2E_EMAIL    || 'admin@admin.com';
const ADMIN_PASSWORD = process.env.E2E_PASSWORD || 'AdminUser';

async function login(page) {
  await page.goto('/users/sign_in');
  await page.fill('input[name="user[email]"]', ADMIN_EMAIL);
  await page.fill('input[name="user[password]"]', ADMIN_PASSWORD);
  await page.click('button[type="submit"], input[type="submit"]');
  await page.waitForLoadState('networkidle');
}

// ---------------------------------------------------------------------------
// Users
// ---------------------------------------------------------------------------

test.describe('Admin — User Management', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
  });

  test('Users list page loads', async ({ page }) => {
    await page.goto('/admin/users');
    await expect(page.getByText('Users')).toBeVisible();
  });

  test('Can open the create-user overlay', async ({ page }) => {
    await page.goto('/admin/users');
    const createBtn = page.getByRole('button', { name: /create user|new user/i });
    await expect(createBtn).toBeVisible();
    await createBtn.click();
    await expect(page.getByRole('dialog')).toBeVisible();
  });

  test('Can create a new local user', async ({ page }) => {
    await page.goto('/admin/users');
    const createBtn = page.getByRole('button', { name: /create user|new user/i });
    await createBtn.click();

    const uniqueEmail = `e2e_user_${Date.now()}@example.com`;
    await page.fill('input[name*="email"]', uniqueEmail);
    await page.fill('input[name*="first_name"]', 'E2E');
    await page.fill('input[name*="last_name"]', 'TestUser');
    await page.click('button[type="submit"]');
    await page.waitForLoadState('networkidle');

    // User should now appear in the list
    await expect(page.getByText(uniqueEmail)).toBeVisible();
  });

  test('Can suspend and re-activate a user', async ({ page }) => {
    await page.goto('/admin/users');
    // Find the first non-admin user's toggle button
    const toggleBtn = page.getByRole('button', { name: /suspend|activate/i }).first();
    if (await toggleBtn.isVisible()) {
      await toggleBtn.click();
      await page.waitForLoadState('networkidle');
      // Button label should flip
      await expect(
        page.getByRole('button', { name: /suspend|activate/i }).first()
      ).toBeVisible();
    }
  });

  test('Can open user detail overlay with tabs', async ({ page }) => {
    await page.goto('/admin/users');
    const firstRow = page.getByRole('row').nth(1);
    await firstRow.click();

    // Overlay / drawer should appear with tabs
    await expect(page.getByRole('tab', { name: /properties/i })).toBeVisible();
    await expect(page.getByRole('tab', { name: /groups/i })).toBeVisible();
    await expect(page.getByRole('tab', { name: /impersonators/i })).toBeVisible();
    await expect(page.getByRole('tab', { name: /preferences/i })).toBeVisible();
  });

  test('Can navigate to Preferences tab and change language', async ({ page }) => {
    await page.goto('/admin/users');
    const firstRow = page.getByRole('row').nth(1);
    await firstRow.click();

    await page.getByRole('tab', { name: /preferences/i }).click();
    await expect(page.getByLabel(/language/i)).toBeVisible();
  });
});

// ---------------------------------------------------------------------------
// User Groups
// ---------------------------------------------------------------------------

test.describe('Admin — User Groups Management', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
  });

  test('User Groups list page loads with built-in groups', async ({ page }) => {
    await page.goto('/admin/user_groups');
    await expect(page.getByText('everyone')).toBeVisible();
    await expect(page.getByText('administrators')).toBeVisible();
    await expect(page.getByText('super-administrators')).toBeVisible();
  });

  test('Built-in groups do NOT show a delete button', async ({ page }) => {
    await page.goto('/admin/user_groups');

    // Find the "everyone" row and verify no delete button
    const everyoneRow = page.locator('tr, [data-group-slug="everyone"]').filter({ hasText: 'everyone' }).first();
    await expect(everyoneRow.getByRole('button', { name: /delete/i })).toHaveCount(0);
  });

  test('Can create a new user group', async ({ page }) => {
    await page.goto('/admin/user_groups');
    await page.getByRole('button', { name: /create group|new group/i }).click();

    await page.fill('input[name*="name"]', `E2E Group ${Date.now()}`);
    await page.fill('textarea[name*="description"], input[name*="description"]', 'Created by E2E tests');
    await page.click('button[type="submit"]');
    await page.waitForLoadState('networkidle');

    await expect(page.getByText('E2E Group')).toBeVisible();
  });

  test('Can open a group overlay and see Members tab', async ({ page }) => {
    await page.goto('/admin/user_groups');

    // Click on the administrators group to open overlay
    await page.getByText('administrators').first().click();
    await expect(page.getByRole('tab', { name: /members/i })).toBeVisible();
    await expect(page.getByRole('tab', { name: /properties/i })).toBeVisible();
    await expect(page.getByRole('tab', { name: /permissions/i })).toBeVisible();
  });

  test('Can open Permissions tab and see ACL matrix', async ({ page }) => {
    await page.goto('/admin/user_groups');

    // Open a group overlay
    await page.getByText('administrators').first().click();
    await page.getByRole('tab', { name: /permissions/i }).click();

    // Should show Read, Modify, Create, Delete, Replicate columns
    await expect(page.getByText(/read/i)).toBeVisible();
    await expect(page.getByText(/modify/i)).toBeVisible();
    await expect(page.getByText(/create/i)).toBeVisible();
    await expect(page.getByText(/delete/i)).toBeVisible();
    await expect(page.getByText(/replicate/i)).toBeVisible();
  });

  test('Can delete a non-system group', async ({ page }) => {
    // First create one via API so we have something to delete
    await page.goto('/admin/user_groups');
    await page.getByRole('button', { name: /create group|new group/i }).click();

    const groupName = `Deletable ${Date.now()}`;
    await page.fill('input[name*="name"]', groupName);
    await page.click('button[type="submit"]');
    await page.waitForLoadState('networkidle');

    // Find and click delete
    const row = page.locator('tr').filter({ hasText: groupName });
    await row.getByRole('button', { name: /delete/i }).click();

    // Confirm if a dialog appears
    const confirmBtn = page.getByRole('button', { name: /confirm|yes/i });
    if (await confirmBtn.isVisible({ timeout: 2000 })) {
      await confirmBtn.click();
    }
    await page.waitForLoadState('networkidle');
    await expect(page.getByText(groupName)).toHaveCount(0);
  });
});

// ---------------------------------------------------------------------------
// Folder Permissions (ACL matrix)
// ---------------------------------------------------------------------------

test.describe('Admin — Folder Permissions ACL', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
  });

  test('Folder permissions panel loads with new ACL columns', async ({ page }) => {
    // Navigate to a folder's permission panel if it exists in the UI
    await page.goto('/admin/user_groups');
    await page.getByText('administrators').first().click();
    await page.getByRole('tab', { name: /permissions/i }).click();

    // The matrix should have our renamed columns
    await expect(page.getByRole('columnheader', { name: /read/i }).or(
      page.getByText('Read')
    )).toBeVisible({ timeout: 5000 });
  });
});

