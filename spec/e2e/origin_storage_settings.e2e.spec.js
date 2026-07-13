// E2E tests for the System Status → "Storage & Edge" tab → "Origin Storage"
// sub-tab.
//
// Covers:
//  - Navigation to /settings/system, "Storage & Edge" tab selection, then
//    the "Origin Storage" sub-tab.
//  - Storage Backend Configuration form renders with the active provider.
//  - The legacy /settings General page still shows System Administration
//    (Service Accounts), plus a redirect notice for the storage section
//    (moved to System Settings).
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

test.describe('Admin — Storage & Edge — Origin Storage', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
    await page.goto('/settings/system');
    await page.waitForLoadState('networkidle');
    await page.getByRole('tab', { name: /storage & edge/i }).click();
  });

  test('Origin Storage sub-tab shows Storage Backend Configuration', async ({ page }) => {
    await page.getByRole('tab', { name: /origin storage/i }).click();

    await expect(page.getByText('Storage Backend Configuration')).toBeVisible();
    await expect(page.getByLabel(/primary storage provider/i)).toBeVisible();
    await expect(page.getByText('System Administration')).not.toBeVisible();
  });

  test('Edge CDN sub-tab remains the default and does not show storage config sections', async ({ page }) => {
    await expect(page.getByText(/target edge provider/i).first()).toBeVisible();
    await expect(page.getByText('Storage Backend Configuration')).not.toBeVisible();
  });

  test('Origin Storage Test Connection and Save & Activate actions are available', async ({ page }) => {
    await page.getByRole('tab', { name: /origin storage/i }).click();

    await expect(page.getByRole('button', { name: /test connection/i })).toBeVisible();
    await expect(page.getByRole('button', { name: /save & activate/i })).toBeVisible();
  });
});

test.describe('Settings — General page', () => {
  test('still shows System Administration and a redirect notice for storage config', async ({ page }) => {
    await login(page);
    await page.goto('/settings');
    await page.waitForLoadState('networkidle');

    await expect(page.getByText('System Administration')).toBeVisible();
    await expect(page.getByText('System Service Accounts')).toBeVisible();
    await expect(page.getByText(/storage backend configuration has moved to/i)).toBeVisible();
    await expect(page.getByRole('button', { name: /go to system settings/i })).toBeVisible();
  });
});
