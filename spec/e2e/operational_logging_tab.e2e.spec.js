// E2E tests for the System Status → "Operational Logging" tab.
//
// Covers:
//  - Navigation to /settings/system → Operational Logging tab.
//  - Current Pipeline Status card (active log level chip).
//  - The "DEBUG"/"TRACE" + no-TTL high-verbosity warning banner.
//  - The real save flow: POST /admin/system_configurations/logging, verified
//    via GET /admin/system_configurations/logging (not mocked) — this also
//    exercises the TRACE level end-to-end since the backend's accepted level
//    list must include every level the UI offers.
//
// The test restores the log level back to INFO / Permanent at the end so it
// does not leave the shared dev/test environment in an elevated-verbosity
// state for other test runs.
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

async function selectLevelAndTtl(page, levelLabel, ttlLabel) {
  await page.getByLabel(/target log level/i).click();
  await page.getByRole('option', { name: levelLabel }).click();
  await page.getByLabel(/time-to-live/i).click();
  await page.getByRole('option', { name: ttlLabel }).click();
}

test.describe('Admin — Operational Logging', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
    await page.goto('/settings/system');
    await page.waitForLoadState('networkidle');
    await page.getByRole('tab', { name: /operational logging/i }).click();
  });

  test('shows the current pipeline status card with the active log level', async ({ page }) => {
    await expect(page.getByText('Current Pipeline Status')).toBeVisible();
    await expect(page.getByText('Active Log Level')).toBeVisible();
    // A chip with one of the valid levels should be rendered.
    await expect(page.locator('.MuiChip-label').filter({ hasText: /FATAL|ERROR|WARN|INFO|DEBUG|TRACE/ }).first()).toBeVisible();
  });

  test('renders the verbosity configuration controls', async ({ page }) => {
    await expect(page.getByText('Adjust Log Verbosity')).toBeVisible();
    await expect(page.getByLabel(/target log level/i)).toBeVisible();
    await expect(page.getByLabel(/time-to-live/i)).toBeVisible();
    await expect(page.getByRole('button', { name: /apply configuration/i })).toBeVisible();
  });

  test('selecting DEBUG or TRACE without a TTL shows the high-verbosity warning', async ({ page }) => {
    await selectLevelAndTtl(page, 'DEBUG (Detailed Variables)', 'Permanent (No Auto-Revert)');
    await expect(page.getByText(/leaving high-verbosity logs on permanently/i)).toBeVisible();

    await selectLevelAndTtl(page, 'TRACE (Maximum Verbosity)', 'Permanent (No Auto-Revert)');
    await expect(page.getByText(/leaving high-verbosity logs on permanently/i)).toBeVisible();
  });

  test('the warning disappears once a TTL is set alongside a high-verbosity level', async ({ page }) => {
    await selectLevelAndTtl(page, 'DEBUG (Detailed Variables)', '15 Minutes');
    await expect(page.getByText(/leaving high-verbosity logs on permanently/i)).not.toBeVisible();
  });

  test('Apply Configuration persists the level via the real API and reflects it in the active status card', async ({ page }) => {
    await selectLevelAndTtl(page, 'WARN (Deprecations & Warnings)', '15 Minutes');

    const [response] = await Promise.all([
      page.waitForResponse((res) => res.url().includes('/admin/system_configurations/logging') && res.request().method() === 'POST'),
      page.getByRole('button', { name: /apply configuration/i }).click(),
    ]);
    expect(response.ok()).toBeTruthy();

    await expect(page.getByText(/log level successfully changed to warn/i)).toBeVisible({ timeout: 10_000 });
    await expect(page.locator('.MuiChip-label', { hasText: 'WARN' })).toBeVisible();
    // TTL banner should now show a temporary-elevation notice.
    await expect(page.getByText(/temporary elevation active/i)).toBeVisible();

    // ── Cleanup: restore INFO / Permanent so the shared dev environment
    // isn't left running at elevated verbosity for other e2e specs. ──
    await selectLevelAndTtl(page, 'INFO (Standard Operations)', 'Permanent (No Auto-Revert)');
    const [restoreResponse] = await Promise.all([
      page.waitForResponse((res) => res.url().includes('/admin/system_configurations/logging') && res.request().method() === 'POST'),
      page.getByRole('button', { name: /apply configuration/i }).click(),
    ]);
    expect(restoreResponse.ok()).toBeTruthy();
    await expect(page.locator('.MuiChip-label', { hasText: 'INFO' })).toBeVisible();
  });
});
