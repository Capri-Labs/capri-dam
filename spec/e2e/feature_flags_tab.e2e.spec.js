// E2E tests for the System Status → "Feature Flags" tab.
//
// IMPORTANT — current implementation status: FeatureFlagsTab.jsx is
// currently a static "coming soon" placeholder (no flags list, no toggle
// controls — both of its buttons are permanently `disabled`). There is no
// real flag data or toggle behaviour to exercise yet, so this spec documents
// and locks in the actual current placeholder UI rather than a
// toggle-a-flag-and-confirm-its-effect flow that doesn't exist in the app
// yet. Once real feature-flag management ships, replace/extend this spec
// with real toggle + effect-confirmation coverage (and note, per product
// context, that flags will initially apply system-wide only — no
// per-tenant/per-site override is planned yet).
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

test.describe('Admin — Feature Flags (placeholder module)', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
    await page.goto('/settings/system');
    await page.waitForLoadState('networkidle');
    await page.getByRole('tab', { name: /feature flags/i }).click();
  });

  test('shows the "Feature Flags & Release Management" placeholder heading and description', async ({ page }) => {
    await expect(page.getByText('Feature Flags & Release Management')).toBeVisible();
    await expect(page.getByText(/decouple deployment from release/i)).toBeVisible();
    await expect(page.getByText(/global maintenance mode/i)).toBeVisible();
  });

  test('"View Active Flags" and "Module in Development" controls are visible but disabled (not yet implemented)', async ({ page }) => {
    const viewFlagsBtn = page.getByRole('button', { name: /view active flags/i });
    const moduleBtn    = page.getByRole('button', { name: /module in development/i });

    await expect(viewFlagsBtn).toBeVisible();
    await expect(viewFlagsBtn).toBeDisabled();

    await expect(moduleBtn).toBeVisible();
    await expect(moduleBtn).toBeDisabled();
  });
});
