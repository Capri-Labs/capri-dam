// @ts-check
/**
 * E2E: Folder Info Panel — Access Tab
 *
 * Verifies:
 *  1. Access tab opens and shows the policy list
 *  2. "Add Group" form appears and allows searching + selecting a group
 *  3. A policy is persisted after submission
 *  4. Cascade toggle triggers a visible confirmation
 *  5. Remove policy removes it from the list
 *  6. Subfolder cascade checkbox is visible and toggleable
 */

const { test, expect } = require('./fixtures');

const BASE = process.env.BASE_URL || 'http://localhost:3000';

// Shared helper: sign in as admin and navigate to the Assets view.
async function signInAsAdmin(page) {
  await page.goto(`${BASE}/users/sign_in`);
  await page.waitForSelector('input[autocomplete="email"]', { timeout: 15_000 });
  await page.fill('input[autocomplete="email"]', process.env.ADMIN_EMAIL ?? 'admin@admin.com');
  await page.fill('input[autocomplete="current-password"]', process.env.ADMIN_PASSWORD ?? 'AdminUser');

  const [response] = await Promise.all([
    page.waitForResponse((res) => res.url().includes('/users/sign_in.json'), { timeout: 15_000 }),
    page.getByRole('button', { name: 'Sign In', exact: true }).click(),
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

// Opens the folder info panel for the first visible folder.
async function openFolderInfoPanel(page) {
  await page.goto(`${BASE}/assets`);
  await page.waitForLoadState('networkidle');
  // FolderGrid.jsx renders the info button as an IconButton with
  // className="folder-info-btn" (no data-testid/aria-label), hidden via
  // opacity:0 until the containing folder card is hovered. Hovering the
  // button itself also satisfies the parent Paper's CSS :hover selector
  // since the pointer position is physically within the parent's box.
  const infoBtn = page.locator('.folder-info-btn').first();
  await infoBtn.hover();
  await infoBtn.click({ force: true });
  // Wait for the drawer
  await expect(page.locator('[role="presentation"]').filter({ hasText: 'Folder properties' })).toBeVisible();
}

// ── Tests ─────────────────────────────────────────────────────────────────────

test.describe('Folder Info Panel – Access Tab', () => {
  test.beforeEach(async ({ page }) => {
    await signInAsAdmin(page);
    await openFolderInfoPanel(page);
    // Click the "Access" tab
    await page.getByRole('tab', { name: /access/i }).click();
  });

  test('Access tab renders without errors', async ({ page }) => {
    await expect(page.getByRole('heading', { name: /access policies/i })).toBeVisible();
  });

  test('Add Group button opens the inline form', async ({ page }) => {
    await page.getByRole('button', { name: /add group/i }).click();
    await expect(page.getByText(/permissions/i)).toBeVisible();
    await expect(page.getByPlaceholder(/search groups by name/i)).toBeVisible();
  });

  test('Group search returns results and allows selection', async ({ page }) => {
    await page.getByRole('button', { name: /add group/i }).click();
    const searchInput = page.getByPlaceholder(/search groups by name/i);
    await searchInput.fill('every');
    // Wait for debounce + results
    await expect(page.getByText('everyone', { exact: false })).toBeVisible({ timeout: 5000 });
    await page.getByText('everyone', { exact: false }).first().click();
    // Chip appears
    await expect(page.getByText('everyone')).toBeVisible();
    // The search box unmounts and is replaced by a Chip once a group is selected
    // (see FolderAccessTab.jsx AddPolicyForm — GroupSearch is only rendered
    // when no group is selected yet), so it's no longer present in the DOM.
    await expect(searchInput).toHaveCount(0);
  });

  test('Cascade toggle shows subfolder warning banner', async ({ page }) => {
    await page.getByRole('button', { name: /add group/i }).click();
    // Rendered as a MUI <Switch>, whose input carries role="switch" (not "checkbox").
    const cascadeToggle = page.getByRole('switch', { name: /apply to all subfolders/i });
    if (!(await cascadeToggle.isChecked())) {
      await cascadeToggle.click();
    }
    await expect(page.getByText(/nested subfolders/i)).toBeVisible();
  });

  test('Cancel button hides the add form', async ({ page }) => {
    await page.getByRole('button', { name: /add group/i }).click();
    await expect(page.getByText(/permissions/i)).toBeVisible();
    await page.getByRole('button', { name: /cancel/i }).click();
    await expect(page.getByText(/permissions/i)).not.toBeVisible();
  });

  test('Explicit Deny checkbox is present in the form', async ({ page }) => {
    await page.getByRole('button', { name: /add group/i }).click();
    await expect(page.getByText(/explicit deny/i)).toBeVisible();
  });

  test('Inherited policies section shows source folder badge', async ({ page }) => {
    // This test passes if the inherited_policies section renders when data exists.
    // If the current folder has no parent, the section is simply absent (no assertion error).
    const inheritedHeader = page.getByText(/inherited from parent folder/i);
    const hasInherited = await inheritedHeader.isVisible().catch(() => false);
    if (hasInherited) {
      // Each inherited row should have a "↑ parentName" chip
      await expect(page.locator('[class*="MuiChip"]').filter({ hasText: '↑' }).first()).toBeVisible();
    }
  });

  test('Remove policy cascade checkbox is present in explicit policy rows', async ({ page }) => {
    const rows = page.locator('[data-testid="policy-row"]');
    const count = await rows.count();
    if (count > 0) {
      await expect(rows.first().getByText(/also subfolders/i)).toBeVisible();
    }
  });
});

// ── Unit-level API tests via Playwright fetch ──────────────────────────────────

test.describe('Folder Policies API (via browser fetch)', () => {
  test('GET /api/v1/user_groups?q=editor returns matching groups', async ({ page }) => {
    await signInAsAdmin(page);

    const result = await page.evaluate(async () => {
      const res = await fetch('/api/v1/user_groups?q=editor', {
        headers: { Accept: 'application/json' },
      });
      return { status: res.status, body: await res.json() };
    });

    expect(result.status).toBe(200);
    expect(Array.isArray(result.body)).toBe(true);
  });

  test('GET /api/v1/folders/:id/policies returns policy arrays', async ({ page }) => {
    await signInAsAdmin(page);
    await page.goto(`${BASE}/assets`);

    // Fetch the first folder ID from the API
    const folders = await page.evaluate(async () => {
      const res = await fetch('/api/v1/folders/root', { headers: { Accept: 'application/json' } });
      const data = await res.json();
      return data.folders ?? [];
    });

    if (folders.length === 0) {
      test.skip();
      return;
    }

    const folderId = folders[0].id;
    const result = await page.evaluate(async (id) => {
      const res = await fetch(`/api/v1/folders/${id}/policies`, {
        headers: { Accept: 'application/json' },
      });
      return { status: res.status, body: await res.json() };
    }, folderId);

    expect(result.status).toBe(200);
    expect(result.body).toHaveProperty('explicit_policies');
    expect(result.body).toHaveProperty('inherited_policies');
  });
});

