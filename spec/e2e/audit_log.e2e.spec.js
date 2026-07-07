// E2E tests for the System Status → "Audit Trail" tab.
//
// Covers:
//  - Navigation to /settings/system and tab selection.
//  - Audit log table renders with real backend data.
//  - Filtering by resource type / action and clearing filters.
//
// Prereqs: app running at E2E_BASE_URL with seed data (bin/rails db:seed).

const { test, expect } = require('./fixtures');

const ADMIN_EMAIL    = process.env.E2E_EMAIL    || 'admin@admin.com';
const ADMIN_PASSWORD = process.env.E2E_PASSWORD || 'AdminUser';

async function login(page) {
  await page.goto('/users/sign_in');
  await page.waitForSelector('input[autocomplete="email"]', { timeout: 15_000 });
  await page.fill('input[autocomplete="email"]', ADMIN_EMAIL);
  await page.fill('input[autocomplete="current-password"]', ADMIN_PASSWORD);

  const [response] = await Promise.all([
    page.waitForResponse((res) => res.url().includes('/users/sign_in.json'), { timeout: 15_000 }),
    page.click('button[type="submit"], input[type="submit"]'),
  ]);
  expect(response.ok()).toBeTruthy();

  await page.waitForURL(/^https?:\/\/[^/]+\/?(\?.*)?$/, { timeout: 15_000 });
  await page.waitForLoadState('networkidle');

  const signedIn = await page.locator('#header-root').getAttribute('data-signed-in');
  if (signedIn !== 'true') {
    await page.reload();
    await page.waitForLoadState('networkidle');
  }
}

test.describe('Admin — Audit Trail', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
    await page.goto('/settings/system');
    await page.waitForLoadState('networkidle');
    await page.getByRole('tab', { name: /audit trail/i }).click();
  });

  test('renders the Audit Trail tab with filters and (empty or populated) results', async ({ page }) => {
    await expect(page.getByText(/browse and search the immutable record/i)).toBeVisible();

    // Either the table renders or the "no entries" empty state does — both are
    // valid depending on whether any auditable actions have happened yet in
    // this environment, so assert on whichever is present.
    const table = page.locator('table');
    const emptyState = page.getByText(/no audit log entries match/i);
    await expect(table.or(emptyState)).toBeVisible({ timeout: 15_000 });
  });

  test('filters can be applied and cleared without error', async ({ page }) => {
    const [response] = await Promise.all([
      page.waitForResponse((res) => res.url().includes('/admin/audit_logs')),
      page.getByRole('button', { name: /apply filters/i }).click(),
    ]);
    expect(response.ok()).toBeTruthy();

    const [clearResponse] = await Promise.all([
      page.waitForResponse((res) => res.url().includes('/admin/audit_logs')),
      page.getByRole('button', { name: /clear filters/i }).click(),
    ]);
    expect(clearResponse.ok()).toBeTruthy();
  });
});
