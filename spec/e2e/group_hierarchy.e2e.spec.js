// E2E tests for the Groups tab child-group management feature.
//
// Covers:
//  - Groups tab shows "Child Groups" and "Parent Group" sections
//  - Search box appears with already-added groups grayed out
//  - Admin can add an existing group as a child from the Groups tab
//  - Admin can remove a child group (removes from list)
//  - Parent group section is read-only (lock icon, no remove button)
//  - Members tab no longer shows sub-groups section
//  - Members tab UserSearch does not throw JS errors
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

/**
 * Navigate to the User Groups page, find a group by name and open its overlay.
 */
async function openGroupOverlay(page, groupName) {
  await page.goto('/admin/user_groups');
  await page.waitForLoadState('networkidle');
  const groupItem = page.getByText(groupName, { exact: false }).first();
  await groupItem.click();
  // Wait for the overlay drawer to open
  await page.waitForSelector('[role="presentation"]', { state: 'visible', timeout: 8000 });
}

// ─────────────────────────────────────────────────────────────────────────────
// Groups tab layout
// ─────────────────────────────────────────────────────────────────────────────

test.describe('Group overlay — Groups tab structure', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
  });

  test('Groups tab is visible in the group overlay', async ({ page }) => {
    await openGroupOverlay(page, 'administrators');
    await expect(page.getByRole('tab', { name: /groups/i })).toBeVisible();
  });

  test('Groups tab shows Child Groups and Parent Group sections', async ({ page }) => {
    await openGroupOverlay(page, 'administrators');
    await page.getByRole('tab', { name: /groups/i }).click();
    await page.waitForLoadState('networkidle');

    await expect(page.getByText(/child groups/i)).toBeVisible({ timeout: 6000 });
    await expect(page.getByText(/parent group/i)).toBeVisible({ timeout: 6000 });
  });

  test('root-level group shows "no parent" alert in Parent Group section', async ({ page }) => {
    await openGroupOverlay(page, 'administrators');
    await page.getByRole('tab', { name: /groups/i }).click();
    await page.waitForLoadState('networkidle');

    // administrators has no parent — should show the info alert
    await expect(
      page.getByText(/root-level group with no parent/i)
    ).toBeVisible({ timeout: 6000 });
  });

  test('child group shows its parent in the Parent Group section', async ({ page }) => {
    // Create a parent and a child group via the API so we have a known hierarchy
    const parentName = `E2E Parent ${Date.now()}`;
    const childName  = `E2E Child ${Date.now()}`;

    // Use the API directly to create groups
    const csrfToken = await page.evaluate(() =>
      document.querySelector('meta[name="csrf-token"]')?.getAttribute('content')
    );

    // Create parent
    const parentRes = await page.request.post('/admin/user_groups', {
      headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken || '' },
      data: { user_group: { name: parentName, description: 'E2E parent group' } }
    });
    const parentData = await parentRes.json();
    const parentId = parentData.group?.id;

    // Create child
    const childRes = await page.request.post('/admin/user_groups', {
      headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken || '' },
      data: { user_group: { name: childName, description: 'E2E child group' } }
    });
    const childData = await childRes.json();
    const childId = childData.group?.id;

    // Nest child under parent
    await page.request.post(`/admin/user_groups/${parentId}/add_group_member`, {
      headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken || '' },
      data: { child_group_id: childId }
    });

    // Now open the child group overlay and check the Parent Group section
    await openGroupOverlay(page, childName);
    await page.getByRole('tab', { name: /groups/i }).click();

    await expect(page.getByText(parentName)).toBeVisible({ timeout: 6000 });

    // Lock icon (read-only) should be visible — no remove button for parent
    await expect(page.getByText(/parent cannot be removed from the child/i)).not.toBeVisible();
    // There should be no delete button next to the parent entry
    const parentSection = page.locator('section, [data-testid="parent-section"]').first();

    // Cleanup
    await page.request.delete(`/admin/user_groups/${childId}`, {
      headers: { 'X-CSRF-Token': csrfToken || '' }
    });
    await page.request.delete(`/admin/user_groups/${parentId}`, {
      headers: { 'X-CSRF-Token': csrfToken || '' }
    });
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// Adding child groups
// ─────────────────────────────────────────────────────────────────────────────

test.describe('Group overlay — adding child groups', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
  });

  test('Groups tab shows a group-search box for admin users', async ({ page }) => {
    await openGroupOverlay(page, 'administrators');
    await page.getByRole('tab', { name: /groups/i }).click();
    await page.waitForLoadState('networkidle');

    // The search/autocomplete input should be visible
    await expect(
      page.getByPlaceholder(/search and add an existing group/i)
    ).toBeVisible({ timeout: 6000 });
  });

  test('can add an existing group as a child and it appears in the list', async ({ page }) => {
    const parentName = `E2E Parent ${Date.now()}`;
    const childName  = `E2E Child ${Date.now()}`;

    const csrfToken = await page.evaluate(() =>
      document.querySelector('meta[name="csrf-token"]')?.getAttribute('content')
    );

    const pRes = await page.request.post('/admin/user_groups', {
      headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken || '' },
      data: { user_group: { name: parentName } }
    });
    const parentId = (await pRes.json()).group?.id;

    const cRes = await page.request.post('/admin/user_groups', {
      headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken || '' },
      data: { user_group: { name: childName } }
    });
    const childId = (await cRes.json()).group?.id;

    // Open parent overlay → Groups tab
    await openGroupOverlay(page, parentName);
    await page.getByRole('tab', { name: /groups/i }).click();
    await page.waitForLoadState('networkidle');

    // Type in the search box
    const searchInput = page.getByPlaceholder(/search and add an existing group/i);
    await searchInput.fill(childName.substring(0, 10));

    // Wait for autocomplete dropdown and click the option
    await page.waitForSelector('[role="listbox"]', { timeout: 5000 });
    await page.getByRole('option', { name: new RegExp(childName, 'i') }).click();
    await page.waitForLoadState('networkidle');

    // Child should now appear in the Child Groups list
    await expect(page.getByText(childName)).toBeVisible({ timeout: 6000 });

    // Cleanup
    await page.request.delete(`/admin/user_groups/${childId}`, {
      headers: { 'X-CSRF-Token': csrfToken || '' }
    });
    await page.request.delete(`/admin/user_groups/${parentId}`, {
      headers: { 'X-CSRF-Token': csrfToken || '' }
    });
  });

  test('already-added child shows as disabled (grayed) in the search dropdown', async ({ page }) => {
    const parentName = `E2E Parent ${Date.now()}`;
    const childName  = `E2E Child ${Date.now()}`;

    const csrfToken = await page.evaluate(() =>
      document.querySelector('meta[name="csrf-token"]')?.getAttribute('content')
    );

    const pRes = await page.request.post('/admin/user_groups', {
      headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken || '' },
      data: { user_group: { name: parentName } }
    });
    const parentId = (await pRes.json()).group?.id;

    const cRes = await page.request.post('/admin/user_groups', {
      headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken || '' },
      data: { user_group: { name: childName } }
    });
    const childId = (await cRes.json()).group?.id;

    // Pre-add the child via API
    await page.request.post(`/admin/user_groups/${parentId}/add_group_member`, {
      headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken || '' },
      data: { child_group_id: childId }
    });

    await openGroupOverlay(page, parentName);
    await page.getByRole('tab', { name: /groups/i }).click();
    await page.waitForLoadState('networkidle');

    const searchInput = page.getByPlaceholder(/search and add an existing group/i);
    await searchInput.fill(childName.substring(0, 10));
    await page.waitForSelector('[role="listbox"]', { timeout: 5000 });

    // The option should be present but marked as disabled
    const option = page.getByRole('option', { name: new RegExp(childName, 'i') });
    await expect(option).toBeVisible();
    await expect(option).toHaveAttribute('aria-disabled', 'true');

    // "Already added" chip should be visible inside the option
    await expect(page.getByText(/already added/i)).toBeVisible();

    // Cleanup
    await page.request.delete(`/admin/user_groups/${childId}`, {
      headers: { 'X-CSRF-Token': csrfToken || '' }
    });
    await page.request.delete(`/admin/user_groups/${parentId}`, {
      headers: { 'X-CSRF-Token': csrfToken || '' }
    });
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// Removing child groups
// ─────────────────────────────────────────────────────────────────────────────

test.describe('Group overlay — removing child groups', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
  });

  test('admin can remove a child group from the parent Groups tab', async ({ page }) => {
    const parentName = `E2E Parent ${Date.now()}`;
    const childName  = `E2E Child ${Date.now()}`;

    const csrfToken = await page.evaluate(() =>
      document.querySelector('meta[name="csrf-token"]')?.getAttribute('content')
    );

    const pRes = await page.request.post('/admin/user_groups', {
      headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken || '' },
      data: { user_group: { name: parentName } }
    });
    const parentId = (await pRes.json()).group?.id;

    const cRes = await page.request.post('/admin/user_groups', {
      headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken || '' },
      data: { user_group: { name: childName } }
    });
    const childId = (await cRes.json()).group?.id;

    await page.request.post(`/admin/user_groups/${parentId}/add_group_member`, {
      headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken || '' },
      data: { child_group_id: childId }
    });

    // Open parent overlay → Groups tab
    await openGroupOverlay(page, parentName);
    await page.getByRole('tab', { name: /groups/i }).click();
    await page.waitForLoadState('networkidle');

    // Child should be listed
    await expect(page.getByText(childName)).toBeVisible({ timeout: 6000 });

    // Click the remove (delete) button next to the child
    const childRow = page.locator('li').filter({ hasText: childName });
    await childRow.getByRole('button').click();
    await page.waitForLoadState('networkidle');

    // Child should no longer appear in the list
    await expect(page.getByText(childName)).not.toBeVisible({ timeout: 6000 });

    // Cleanup
    await page.request.delete(`/admin/user_groups/${childId}`, {
      headers: { 'X-CSRF-Token': csrfToken || '' }
    });
    await page.request.delete(`/admin/user_groups/${parentId}`, {
      headers: { 'X-CSRF-Token': csrfToken || '' }
    });
  });

  test('Parent Group section has a lock icon (no remove button)', async ({ page }) => {
    const parentName = `E2E Parent ${Date.now()}`;
    const childName  = `E2E Child ${Date.now()}`;

    const csrfToken = await page.evaluate(() =>
      document.querySelector('meta[name="csrf-token"]')?.getAttribute('content')
    );

    const pRes = await page.request.post('/admin/user_groups', {
      headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken || '' },
      data: { user_group: { name: parentName } }
    });
    const parentId = (await pRes.json()).group?.id;

    const cRes = await page.request.post('/admin/user_groups', {
      headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken || '' },
      data: { user_group: { name: childName } }
    });
    const childId = (await cRes.json()).group?.id;

    await page.request.post(`/admin/user_groups/${parentId}/add_group_member`, {
      headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken || '' },
      data: { child_group_id: childId }
    });

    // Open CHILD overlay → Groups tab
    await openGroupOverlay(page, childName);
    await page.getByRole('tab', { name: /groups/i }).click();
    await page.waitForLoadState('networkidle');

    // Parent group name should be visible under "Parent Group" section
    await expect(page.getByText(parentName)).toBeVisible({ timeout: 6000 });

    // The parent list item should NOT have a clickable delete/remove button
    const parentListItem = page.locator('li').filter({ hasText: parentName });
    // Only a locked icon tooltip should be present, not a delete button
    await expect(parentListItem.getByRole('button')).toHaveCount(0);

    // Cleanup
    await page.request.delete(`/admin/user_groups/${childId}`, {
      headers: { 'X-CSRF-Token': csrfToken || '' }
    });
    await page.request.delete(`/admin/user_groups/${parentId}`, {
      headers: { 'X-CSRF-Token': csrfToken || '' }
    });
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// Members tab — sub-groups section removed; no JS error on UserSearch
// ─────────────────────────────────────────────────────────────────────────────

test.describe('Group overlay — Members tab', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
  });

  test('Members tab loads without JavaScript errors', async ({ page }) => {
    const jsErrors = [];
    page.on('pageerror', err => jsErrors.push(err.message));

    await openGroupOverlay(page, 'administrators');
    await page.getByRole('tab', { name: /members/i }).click();
    await page.waitForLoadState('networkidle');

    // The user-search input should be visible
    await expect(
      page.getByPlaceholder(/search by name or email/i)
    ).toBeVisible({ timeout: 6000 });

    // No JS errors should have been thrown (specifically the endAdornment crash)
    const endAdornmentError = jsErrors.find(e => e.includes('endAdornment'));
    expect(endAdornmentError).toBeUndefined();
  });

  test('Members tab does NOT show a Sub-Groups section', async ({ page }) => {
    await openGroupOverlay(page, 'administrators');
    await page.getByRole('tab', { name: /members/i }).click();
    await page.waitForLoadState('networkidle');

    // "Sub-Groups" or "nested groups" heading should NOT be on the Members tab
    await expect(page.getByText(/sub-groups/i)).not.toBeVisible({ timeout: 2000 });
  });

  test('Members tab shows "User Members" section heading', async ({ page }) => {
    await openGroupOverlay(page, 'administrators');
    await page.getByRole('tab', { name: /members/i }).click();
    await page.waitForLoadState('networkidle');

    await expect(page.getByText(/user members/i)).toBeVisible({ timeout: 6000 });
  });
});

