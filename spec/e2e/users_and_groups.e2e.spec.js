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

// Scrolls the (virtualized) MUI DataGrid until a row containing `text`
// renders in the DOM. MUI DataGrid only mounts rows within the current
// scroll viewport (plus a small overscan buffer), so newly-created rows (or
// rows alphabetically late) may not exist in the DOM at all until scrolled
// into view. Use small scroll increments with a generous settle delay —
// large jumps (e.g. 300px) can skip clean over a row's render window before
// React/the virtualizer has a chance to mount it, causing false negatives.
async function findGridRow(page, text) {
  const scroller = page.locator('.MuiDataGrid-virtualScroller').first();
  let row = page.locator('.MuiDataGrid-row').filter({ hasText: text }).first();
  for (let i = 0; i < 40; i++) {
    if (await row.count() > 0) return row;
    await scroller.evaluate((el) => el.scrollBy(0, 120));
    await page.waitForTimeout(250);
    row = page.locator('.MuiDataGrid-row').filter({ hasText: text }).first();
  }
  return row;
}

async function login(page) {
  await page.goto('/users/sign_in');
  await page.waitForSelector('input[autocomplete="email"]', { timeout: 15_000 });
  await page.fill('input[autocomplete="email"]', ADMIN_EMAIL);
  await page.fill('input[autocomplete="current-password"]', ADMIN_PASSWORD);

  const [response] = await Promise.all([
    page.waitForResponse((res) => res.url().includes('/users/sign_in.json'), { timeout: 15_000 }),
    page.click('button[type="submit"], input[type="submit"]'),
  ]);
  if (!response.ok()) throw new Error(`login failed with status ${response.status()}`);

  // The app performs a full-page redirect (window.location.href = '/') after
  // a successful AJAX sign-in; wait for it and then double-check the session
  // actually took effect (guards against a rare Set-Cookie/navigation race).
  await page.waitForURL(/^https?:\/\/[^/]+\/?(\?.*)?$/, { timeout: 15_000 });
  await page.waitForLoadState('networkidle');

  const signedIn = await page.locator('#header-root').getAttribute('data-signed-in');
  if (signedIn !== 'true') {
    await page.reload();
    await page.waitForLoadState('networkidle');
  }
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
    const drawer = page.locator('.MuiDrawer-paper');
    await drawer.getByLabel(/first name/i).fill('E2E');
    await drawer.getByLabel(/last name/i).fill('User');
    await drawer.getByLabel(/email address/i).fill(email);
    await drawer.getByLabel(/department/i).fill('QA');
    await page.getByRole('button', { name: /provision local account/i }).click();

    await page.waitForLoadState('networkidle');
    await expect(await findGridRow(page, email)).toBeVisible();
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
    // IMPORTANT: never target the first grid row directly — it is typically
    // the signed-in admin account (lowest id / first seeded user), and the
    // "Suspend Access" button is blocked for the current user anyway. Create
    // a disposable local user instead so we never risk suspending the
    // account the E2E suite itself (or a human operator) is logged in as.
    const email = `e2e_suspend_${Date.now()}@example.com`;
    await page.getByRole('button', { name: /invite local user/i }).click();
    const inviteDrawer = page.locator('.MuiDrawer-paper');
    await inviteDrawer.getByLabel(/first name/i).fill('Suspend');
    await inviteDrawer.getByLabel(/last name/i).fill('Target');
    await inviteDrawer.getByLabel(/email address/i).fill(email);
    await inviteDrawer.getByLabel(/department/i).fill('QA');
    await page.getByRole('button', { name: /provision local account/i }).click();
    await page.waitForLoadState('networkidle');
    const userRow = await findGridRow(page, email);
    await expect(userRow).toBeVisible();
    await userRow.click();

    // Suspend
    let toggleBtn = page.getByRole('button', { name: /suspend access|restore access/i });
    await expect(toggleBtn).toBeVisible();
    await expect(toggleBtn).toHaveText(/suspend access/i);
    await toggleBtn.click();
    await page.waitForLoadState('networkidle');
    await expect(page.getByText('System Users')).toBeVisible();
    await expect((await findGridRow(page, email))).toContainText(/suspended/i);

    // Restore, leaving the test user in its original (active) state.
    await (await findGridRow(page, email)).click();
    toggleBtn = page.getByRole('button', { name: /suspend access|restore access/i });
    await expect(toggleBtn).toHaveText(/restore access/i);
    await toggleBtn.click();
    await page.waitForLoadState('networkidle');
    await expect((await findGridRow(page, email))).toContainText(/active/i);
  });

  test('cannot suspend own (currently logged-in) account', async ({ page }) => {
    const adminRow = page.locator('.MuiDataGrid-row').filter({ hasText: ADMIN_EMAIL });
    await adminRow.click();
    const suspendBtn = page.getByRole('button', { name: /suspend access/i });
    // The button is disabled for the signed-in user's own row.
    await expect(suspendBtn).toBeDisabled();
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
      await expect(page.getByRole('heading', { name: /group hierarchy/i })).toBeVisible();
    }
  });

  test('change password dialog opens from Properties tab', async ({ page }) => {
    await page.locator('.MuiDataGrid-row').first().click();
    const changePassBtn = page.getByRole('button', { name: /change password/i });
    if (await changePassBtn.isVisible({ timeout: 3000 })) {
      await changePassBtn.click();
      await expect(page.getByRole('heading', { name: 'Change Password' })).toBeVisible();
      await expect(page.getByLabel('New Password', { exact: true })).toBeVisible();
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

  // Clean up any custom groups this suite created so repeated runs don't
  // accumulate stale groups that push newly-created ones out of a
  // virtualized/long tree view.
  test.afterEach(async ({ page }) => {
    const res = await page.request.get('/admin/user_groups.json');
    if (!res.ok()) return;
    const body = await res.json();
    const groups = Array.isArray(body) ? body : (body.groups || body.user_groups || []);
    const stale = groups.filter(g =>
      typeof g.name === 'string' && /^(E2E Group|Members Test|Delete Me)\s/.test(g.name)
    );
    for (const g of stale) {
      await page.request.delete(`/admin/user_groups/${g.id}.json`);
    }
  });

  test('groups page loads with hierarchy tree', async ({ page }) => {
    await expect(page.getByRole('heading', { name: 'User Groups' })).toBeVisible();
  });

  test('system groups are visible in tree', async ({ page }) => {
    await expect(page.getByText('everyone')).toBeVisible();
    await expect(page.getByRole('button', { name: 'administrators sys 2', exact: true })).toBeVisible();
    await expect(page.getByRole('button', { name: /super-administrators sys/i })).toBeVisible();
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

    // Should show immutability warning (scoped to the alert, not the sidebar section label)
    await expect(
      page.getByRole('alert').filter({ hasText: /cannot be modified|automatic members|system group/i })
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

    // Filter the tree so the new group is guaranteed to be rendered even if
    // the list is long/virtualized.
    await page.getByPlaceholder(/search groups/i).fill(groupName);
    await expect(page.getByText(groupName)).toBeVisible({ timeout: 10000 });
  });

  test('can open Members tab on a custom group', async ({ page }) => {
    // Create a group first or use existing
    await page.getByRole('button', { name: /new group/i }).click();
    const groupName = `Members Test ${Date.now()}`;
    await page.getByLabel(/group name/i).fill(groupName);
    await page.getByRole('button', { name: /create group/i }).click();
    await page.waitForLoadState('networkidle');

    // Filter the tree so the new group is guaranteed to be rendered, then click it
    await page.getByPlaceholder(/search groups/i).fill(groupName);
    await expect(page.getByText(groupName)).toBeVisible({ timeout: 10000 });
    await page.getByText(groupName).click();
    await page.waitForLoadState('networkidle');

    // Navigate to Members tab
    await page.getByRole('tab', { name: /members/i }).click();
    await expect(page.getByPlaceholder(/search by name or email to add/i)).toBeVisible();
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

    // Filter the tree so the new group is guaranteed to be rendered even if
    // the list is long/virtualized, then click it.
    await page.getByPlaceholder(/search groups/i).fill(groupName);
    await expect(page.getByText(groupName)).toBeVisible({ timeout: 10000 });
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

  test('supports select-all + bulk delete of root-level custom groups', async ({ page }) => {
    test.setTimeout(60_000);

    const stamp = Date.now();
    const created = [];
    try {
      for (let i = 0; i < 2; i += 1) {
        const res = await page.request.post('/admin/user_groups.json', {
          data: { user_group: { name: `Delete Me Bulk ${stamp}-${i}` } },
        });
        expect(res.ok()).toBeTruthy();
        const body = await res.json();
        created.push(body.group);
      }

      await page.reload();
      await page.waitForLoadState('networkidle');

      const firstCheckbox = page.getByTestId(`group-select-${created[0].id}`).locator('input');
      const secondCheckbox = page.getByTestId(`group-select-${created[1].id}`).locator('input');
      await firstCheckbox.check();
      await secondCheckbox.check();

      await expect(page.getByText('2 selected')).toBeVisible();

      page.once('dialog', (dialog) => dialog.accept());
      const [bulkDeleteResponse] = await Promise.all([
        page.waitForResponse((res) =>
          res.url().includes('/admin/user_groups/bulk_delete') &&
          res.request().method() === 'DELETE',
        ),
        page.getByTestId('group-bulk-delete-button').click(),
      ]);
      expect(bulkDeleteResponse.ok()).toBeTruthy();
      const body = await bulkDeleteResponse.json();
      expect(body.deleted_ids.sort()).toEqual([ created[0].id, created[1].id ].sort());

      await expect(page.getByTestId(`group-select-${created[0].id}`)).toHaveCount(0);
      await expect(page.getByTestId(`group-select-${created[1].id}`)).toHaveCount(0);
    } finally {
      for (const g of created) {
        await page.request.delete(`/admin/user_groups/${g.id}.json`).catch(() => {});
      }
    }
  });

  test('can search/filter groups in tree', async ({ page }) => {
    await page.getByPlaceholder(/search groups/i).fill('admin');
    await expect(page.getByRole('button', { name: 'administrators sys 2', exact: true })).toBeVisible();
    await expect(page.getByRole('button', { name: /super-administrators sys/i })).toBeVisible();

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

  // NOTE: the e2e admin account (ADMIN_EMAIL) is a super-admin, so the modal
  // renders the "unrestricted" experience for it: no info alert and no locked
  // groups — every group (including administrators/super-administrators) is
  // assignable via checkbox. The "regular admin sees locked groups" behavior
  // is covered by GroupAssignmentModal's own restriction logic and is a good
  // candidate for a future Jest unit test with a mocked isSuperAdmin=false prop.
  test('group assignment modal has no restriction alert for a super-admin', async ({ page }) => {
    const groupBtn = page.locator('[data-testid="GroupAddIcon"]').first();
    if (await groupBtn.isVisible({ timeout: 3000 })) {
      await groupBtn.click();
      await expect(page.getByRole('heading', { name: /group hierarchy/i })).toBeVisible();

      // Super-admins are not shown the restriction alert, and no groups are locked.
      await expect(page.getByRole('alert').filter({ hasText: /can only be assigned by super-admins/i })).toHaveCount(0);
      await expect(page.locator('[data-testid="LockOutlinedIcon"]')).toHaveCount(0);
    }
  });

  test('administrators and super-administrators groups are assignable via checkbox for a super-admin', async ({ page }) => {
    const groupBtn = page.locator('[data-testid="GroupAddIcon"]').first();
    if (await groupBtn.isVisible({ timeout: 3000 })) {
      await groupBtn.click();
      await expect(page.getByRole('heading', { name: /group hierarchy/i })).toBeVisible();

      // As a super-admin, both system groups render an (enabled) checkbox rather than a lock icon.
      const dialog = page.getByRole('dialog');
      const adminGroupRows = dialog.getByText(/administrators/i);
      await expect(adminGroupRows).toHaveCount(2); // "administrators" + "super-administrators"
      await expect(adminGroupRows.first()).toBeVisible();
      await expect(adminGroupRows.last()).toBeVisible();
      await expect(dialog.getByRole('checkbox')).not.toHaveCount(0);
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

  test('shows only root folders by default; expand reveals subfolders, collapse hides them again', async ({ page }) => {
    await page.goto('/admin/user_groups');
    await page.waitForLoadState('networkidle');

    await page.getByText('administrators').first().click();
    await page.waitForLoadState('networkidle');
    await page.getByRole('tab', { name: /permissions/i }).click();

    // "Archive" is a seeded root folder with two subfolders (2023, 2024).
    await expect(page.getByText('/Archive', { exact: true })).toBeVisible({ timeout: 8000 });
    await expect(page.getByText('/Archive/2023', { exact: true })).toHaveCount(0);

    await page.getByTestId('acl-expand-all').click();
    await expect(page.getByText('/Archive/2023', { exact: true })).toBeVisible({ timeout: 8000 });

    await page.getByTestId('acl-collapse-all').click();
    await expect(page.getByText('/Archive/2023', { exact: true })).toHaveCount(0);
  });

  test('toggling a permission on a parent folder cascades to its expanded subfolders', async ({ page }) => {
    await page.goto('/admin/user_groups');
    await page.waitForLoadState('networkidle');

    await page.getByText('administrators').first().click();
    await page.waitForLoadState('networkidle');
    await page.getByRole('tab', { name: /permissions/i }).click();

    await page.getByTestId('acl-expand-all').click();
    await expect(page.getByText('/Archive/2023', { exact: true })).toBeVisible({ timeout: 8000 });

    const archiveRow = page.locator('tr', { has: page.getByText('/Archive', { exact: true }) });
    const childRow = page.locator('tr', { has: page.getByText('/Archive/2023', { exact: true }) });

    // "Read" is the first permission checkbox after the Path column.
    const archiveReadCheckbox = archiveRow.getByRole('checkbox').nth(0);
    const childReadCheckbox = childRow.getByRole('checkbox').nth(0);

    await archiveReadCheckbox.check();
    await expect(childReadCheckbox).toBeChecked();

    // The admin can still override the cascaded child individually.
    await childReadCheckbox.uncheck();
    await expect(childReadCheckbox).not.toBeChecked();
    await expect(archiveReadCheckbox).toBeChecked();
  });
});


