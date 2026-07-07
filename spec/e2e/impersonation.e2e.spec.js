/**
 * Impersonation E2E — tests the full admin-impersonates-user flow.
 *
 * Coverage:
 *   1. Admin opens a user drawer → Impersonators tab loads a user list
 *      (previously broken: search box was a plain text field that fetched
 *       all users client-side; now it's the UserSearch autocomplete).
 *   2. Admin starts an impersonation session from the Impersonators tab.
 *   3. Impersonation banner is visible on every page.
 *   4. Admin ends the impersonation session — banner disappears.
 *   5. Super-admin cannot impersonate another super-admin.
 *   6. Admin cannot impersonate a super-admin.
 */

const { test, expect } = require('./fixtures');

const BASE_URL    = process.env.BASE_URL    || 'http://localhost:3000';
const ADMIN_EMAIL = process.env.ADMIN_EMAIL || 'admin@admin.com';
const ADMIN_PASS  = process.env.ADMIN_PASS  || 'AdminUser';

const SUPER_EMAIL = process.env.SUPER_EMAIL || 'superadmin@example.com';
const SUPER_PASS  = process.env.SUPER_PASS  || 'Password123!';

const TARGET_EMAIL = process.env.TARGET_EMAIL || 'user@example.com';

// ─── Helpers ──────────────────────────────────────────────────────────────────

async function login(page, email, password) {
  await page.goto(`${BASE_URL}/users/sign_in`);
  await page.waitForSelector('input[autocomplete="email"]', { timeout: 15_000 });
  await page.fill('input[autocomplete="email"]',    email);
  await page.fill('input[autocomplete="current-password"]', password);

  const [response] = await Promise.all([
    page.waitForResponse((res) => res.url().includes('/users/sign_in.json'), { timeout: 15_000 }),
    page.click('button[type="submit"]'),
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

// The Admin Users DataGrid virtualizes rows (MUI DataGrid only renders rows
// currently scrolled into the viewport), so with 19+ seeded users, rows near
// the bottom (alphabetically-late emails like "user@example.com") are not in
// the DOM at all until scrolled into view — filter({hasText}) alone times out.
// Scroll the grid's virtual scroller incrementally until the row appears.
async function findGridRow(page, text) {
  const scroller = page.locator('.MuiDataGrid-virtualScroller');
  for (let i = 0; i < 20; i++) {
    const row = page.locator('.MuiDataGrid-row').filter({ hasText: text });
    if (await row.count() > 0) return row.first();
    await scroller.evaluate((el) => el.scrollBy(0, 300));
    await page.waitForTimeout(150);
  }
  throw new Error(`Row containing "${text}" not found in the Admin Users grid after scrolling`);
}

async function openUserDrawer(page, email) {
  await page.goto(`${BASE_URL}/admin/users`);
  // Wait for the DataGrid to appear
  await page.waitForSelector('[data-testid="users-grid"], .MuiDataGrid-root', { timeout: 10_000 });
  // Click the row matching the target user's email
  const row = await findGridRow(page, email);
  await row.click();
  // The drawer should open
  await page.waitForSelector('[role="presentation"] .MuiDrawer-paper', { timeout: 5_000 });
}

// ─── Tests ────────────────────────────────────────────────────────────────────

test.describe('Impersonation Engine', () => {

  test('Impersonators tab shows autocomplete search, not broken email field', async ({ page }) => {
    await login(page, ADMIN_EMAIL, ADMIN_PASS);
    await openUserDrawer(page, TARGET_EMAIL);

    // Click "Impersonators" tab (index 3)
    const tabs = page.locator('[role="tablist"] [role="tab"]');
    await tabs.nth(3).click();

    // The OLD broken field was <TextField placeholder="Email of user to grant…">
    // The NEW correct component is the MUI Autocomplete (UserSearch)
    await expect(
      page.locator('[placeholder="Search by name or email…"]').first()
    ).toBeVisible({ timeout: 5_000 });

    // The plain-text "Grant" button next to the old field should NOT exist
    await expect(page.locator('button', { hasText: 'Grant' })).toHaveCount(0);
  });

  test('Autocomplete returns users when typing in Impersonators tab', async ({ page }) => {
    await login(page, ADMIN_EMAIL, ADMIN_PASS);
    await openUserDrawer(page, TARGET_EMAIL);

    const tabs = page.locator('[role="tablist"] [role="tab"]');
    await tabs.nth(3).click();

    const searchInput = page.locator('[placeholder="Search by name or email…"]').first();
    await searchInput.fill('admin');

    // Wait for the autocomplete dropdown to open with options
    await expect(
      page.locator('[role="listbox"] [role="option"]').first()
    ).toBeVisible({ timeout: 5_000 });
  });

  test('Admin can start impersonation → banner appears', async ({ page }) => {
    await login(page, ADMIN_EMAIL, ADMIN_PASS);
    await openUserDrawer(page, TARGET_EMAIL);

    const tabs = page.locator('[role="tablist"] [role="tab"]');
    await tabs.nth(3).click();

    // Click the "Impersonate <name>" button
    const impersonateBtn = page.locator('button').filter({ hasText: /Impersonate/ }).last();
    await expect(impersonateBtn).toBeVisible({ timeout: 5_000 });
    await impersonateBtn.click();

    // Wait for redirect to dashboard
  await page.waitForFunction(
    () => !document.querySelector('input[autocomplete="email"]'),
    { timeout: 15_000 },
  );
  await page.waitForLoadState('networkidle');

    // The red impersonation banner should be visible
    await expect(page.locator('[role="alert"]').filter({ hasText: 'IMPERSONATION ACTIVE' }))
      .toBeVisible({ timeout: 5_000 });
  });

  test('Impersonation banner persists on navigation', async ({ page }) => {
    await login(page, ADMIN_EMAIL, ADMIN_PASS);
    await openUserDrawer(page, TARGET_EMAIL);

    const tabs = page.locator('[role="tablist"] [role="tab"]');
    await tabs.nth(3).click();

    const impersonateBtn = page.locator('button').filter({ hasText: /Impersonate/ }).last();
    await impersonateBtn.click();
    await page.waitForFunction(
    () => !document.querySelector('input[autocomplete="email"]'),
    { timeout: 15_000 },
  );
  await page.waitForLoadState('networkidle');

    // Confirm the impersonation session has actually taken effect (banner
    // visible on the landing page) before navigating away — this guards
    // against a race where the session cookie hasn't fully committed yet,
    // which would otherwise make the /folders assertion below flaky.
    await expect(page.locator('[role="alert"]').filter({ hasText: 'IMPERSONATION ACTIVE' }))
      .toBeVisible({ timeout: 10_000 });

    // Navigate to folders — banner must still be visible
    await page.goto(`${BASE_URL}/folders`);
    await page.waitForLoadState('networkidle');
    await expect(page.locator('[role="alert"]').filter({ hasText: 'IMPERSONATION ACTIVE' }))
      .toBeVisible({ timeout: 15_000 });
  });

  test('End Impersonation button clears the session and removes the banner', async ({ page }) => {
    await login(page, ADMIN_EMAIL, ADMIN_PASS);
    await openUserDrawer(page, TARGET_EMAIL);

    const tabs = page.locator('[role="tablist"] [role="tab"]');
    await tabs.nth(3).click();

    const impersonateBtn = page.locator('button').filter({ hasText: /Impersonate/ }).last();
    await impersonateBtn.click();
    await page.waitForFunction(
    () => !document.querySelector('input[autocomplete="email"]'),
    { timeout: 15_000 },
  );
  await page.waitForLoadState('networkidle');

    // Click End Impersonation
    await page.locator('button', { hasText: 'End Impersonation' }).click();
    await page.waitForURL(`${BASE_URL}/admin/users`, { timeout: 10_000 });

    // Banner must be gone
    await expect(page.locator('[role="alert"]').filter({ hasText: 'IMPERSONATION ACTIVE' }))
      .toHaveCount(0);
  });

  test('Admin cannot impersonate a super-admin — button is hidden', async ({ page }) => {
    await login(page, ADMIN_EMAIL, ADMIN_PASS);
    await openUserDrawer(page, SUPER_EMAIL);

    const tabs = page.locator('[role="tablist"] [role="tab"]');
    await tabs.nth(3).click();

    // The Impersonate button must be absent for super-admins
    await expect(page.locator('button').filter({ hasText: /Impersonate/ }))
      .toHaveCount(0, { timeout: 3_000 });

    // A guard message should appear
    await expect(page.locator('text=Super-admin accounts cannot be configured'))
      .toBeVisible({ timeout: 3_000 });
  });

});

// ─── Profile Page E2E ─────────────────────────────────────────────────────────

test.describe('Profile Page (/profile)', () => {

  test('All 4 tabs render without errors', async ({ page }) => {
    await login(page, ADMIN_EMAIL, ADMIN_PASS);
    await page.goto(`${BASE_URL}/profile`);
    await page.waitForSelector('[role="tablist"]', { timeout: 10_000 });

    const tabLabels = ['Personal Details', 'Localization', 'Security & Access', 'My Activity'];
    for (let i = 0; i < tabLabels.length; i++) {
      await page.locator('[role="tablist"] [role="tab"]').nth(i).click();
      await expect(page.locator('[role="tabpanel"]').or(page.locator('[data-tab-panel]'))).toBeVisible({ timeout: 3_000 });
    }
  });

  test('Can create and see a Personal Access Token', async ({ page }) => {
    await login(page, ADMIN_EMAIL, ADMIN_PASS);
    await page.goto(`${BASE_URL}/profile`);

    // Navigate to Security & Access tab
    await page.locator('[role="tab"]').filter({ hasText: 'Security' }).click();

    // Click "New Token"
    await page.locator('button', { hasText: 'New Token' }).click();
    await page.waitForSelector('[role="dialog"]', { timeout: 5_000 });

    await page.fill('[label="Token Name"], input[placeholder*="CI/CD pipeline"]', 'E2E Test Token');
    await page.locator('[role="dialog"] button').filter({ hasText: 'Create Token' }).click();

    // The one-time reveal alert should appear
    await expect(page.locator('[role="alert"]').filter({ hasText: 'Copy this token now' }))
      .toBeVisible({ timeout: 5_000 });

    // The token should start with dat_
    const tokenText = await page.locator('[role="alert"] code').textContent();
    expect(tokenText).toMatch(/^dat_/);
  });

});

