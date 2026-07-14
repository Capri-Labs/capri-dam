// E2E tests for the System Status → "Storage & Edge" tab → "Edge CDN" sub-tab
// → Fastly "Image Optimizer Formats" (AVIF delivery) checkboxes.
//
// Covers:
//  - Navigation to /settings/system, "Storage & Edge" tab, Edge CDN sub-tab
//    (the default), with the Fastly provider selected.
//  - The WebP/AVIF format checkboxes render and are togglable.
//  - Saving persists the selected formats via the real
//    PUT /api/v1/cdn_configurations call (verified via a real reload, not a
//    mock), i.e. the formerly-simulated tab now round-trips through the API.
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

test.describe('Admin — Storage & Edge — Edge CDN — Image Optimizer Formats', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
    await page.goto('/settings/system');
    await page.waitForLoadState('networkidle');
    await page.getByRole('tab', { name: /storage & edge/i }).click();
    await page.getByRole('tab', { name: /edge cdn/i }).click();

    // Fastly is the default/active provider in this environment's seed data,
    // so its credentials panel (including the format checkboxes) is already
    // visible without needing to change the provider dropdown.
    await expect(page.getByText('Fastly CDN')).toBeVisible();
  });

  test('shows WebP and AVIF format checkboxes for the Fastly provider', async ({ page }) => {
    await expect(page.getByText(/image optimizer formats/i)).toBeVisible();
    await expect(page.getByRole('checkbox', { name: 'webp' })).toBeVisible();
    await expect(page.getByRole('checkbox', { name: 'avif' })).toBeVisible();
  });

  test('toggling AVIF and saving persists the selection via the real API', async ({ page }) => {
    const avifCheckbox = page.getByRole('checkbox', { name: 'avif' });
    const wasChecked = await avifCheckbox.isChecked();
    if (wasChecked) await avifCheckbox.uncheck();

    await avifCheckbox.check();

    const [response] = await Promise.all([
      page.waitForResponse((res) => res.url().includes('/api/v1/cdn_configurations') && res.request().method() === 'PUT'),
      page.getByRole('button', { name: /save cdn settings/i }).click(),
    ]);
    expect(response.ok()).toBeTruthy();

    await expect(page.getByText(/fastly configuration updated/i)).toBeVisible();

    // Reload to confirm the checkbox state was actually persisted server-side,
    // not just held in local component state.
    await page.reload();
    await page.waitForLoadState('networkidle');
    await page.getByRole('tab', { name: /storage & edge/i }).click();
    await page.getByRole('tab', { name: /edge cdn/i }).click();

    await expect(page.getByRole('checkbox', { name: 'avif' })).toBeChecked();
  });
});
