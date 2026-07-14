// E2E smoke test for the new Admin → "Security Policies" screen (/admin/policies).
//
// Covers:
//  - Navigation to /admin/policies renders without error and highlights the
//    "Security Policies" nav item.
//  - The group picker list renders (backed by the existing, already-tested
//    GET /admin/user_groups.json endpoint — no new backend API here).
//  - Selecting a group renders the ACL permission matrix (the existing,
//    already-tested AclMatrix component, reused as-is from the Group
//    Permissions tab).
//
// Prereqs: app running at E2E_BASE_URL with seed data (bin/rails db:seed),
// which guarantees at least the "Everyone" system group exists.

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

test.describe('Admin — Security Policies', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
  });

  test('loads the group list and highlights the nav item', async ({ page }) => {
    const [response] = await Promise.all([
      page.waitForResponse((res) => res.url().includes('/admin/user_groups.json')),
      page.goto('/admin/policies'),
    ]);
    expect(response.ok()).toBeTruthy();
    await page.waitForLoadState('networkidle');

    await expect(page.locator('#react-sidebar-root[data-active-view="Security Policies"]')).toHaveCount(1);
    await expect(page.getByText('everyone', { exact: true })).toBeVisible();
  });

  test('selecting a group renders its permission matrix', async ({ page }) => {
    await page.goto('/admin/policies');
    await page.waitForLoadState('networkidle');

    await page.getByText('everyone', { exact: true }).click();

    await expect(page.getByText(/permissions for/i)).toBeVisible();
    await expect(page.getByRole('progressbar')).toHaveCount(0);
    await expect(page.locator('table, [role="table"]').first()).toBeVisible();
  });
});
