// E2E tests for the System Status → "System Observability" tab.
//
// Covers:
//  - Navigation to /settings/system (default tab — no explicit click needed,
//    but we click it anyway for parity/clarity with the other tab specs).
//  - Diagnostic vitals cards (Application Node, PostgreSQL, Redis & Sidekiq,
//    ActiveStorage) populated from the real GET /admin/system_status.json
//    endpoint.
//  - "Refresh Vitals" re-fetches diagnostics.
//  - "Initiate Application Reload" (soft restart) confirm + real
//    POST /admin/system_status/restart_server round-trip.
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

test.describe('Admin — System Observability', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
    await page.goto('/settings/system');
    await page.waitForLoadState('networkidle');
    await page.getByRole('tab', { name: /system observability/i }).click();
  });

  test('renders the four infrastructure vitals cards populated from the real diagnostics endpoint', async ({ page }) => {
    await expect(page.getByText('Application Node')).toBeVisible();
    await expect(page.getByText('Puma Rack')).toBeVisible();

    await expect(page.getByText('PostgreSQL')).toBeVisible();
    await expect(page.getByText('Redis & Sidekiq')).toBeVisible();
    await expect(page.getByText('ActiveStorage')).toBeVisible();

    // Pool/latency captions confirm the real backend payload was rendered,
    // not just static labels.
    await expect(page.getByText(/pool:/i)).toBeVisible();
    await expect(page.getByText(/queue depth:/i)).toBeVisible();
  });

  test('"Refresh Vitals" re-fetches diagnostics and confirms via a success toast', async ({ page }) => {
    await expect(page.getByText('Application Node')).toBeVisible();
    await page.getByRole('button', { name: /refresh vitals/i }).click();
    await expect(page.getByText(/infrastructure matrices refreshed successfully/i)).toBeVisible({ timeout: 10_000 });
  });

  test('Server Engineering Controls section is present with a restart action', async ({ page }) => {
    await expect(page.getByText('Server Engineering Controls')).toBeVisible();
    await expect(page.getByRole('button', { name: /initiate application reload/i })).toBeVisible();
  });

  test('declining the restart confirmation does not call the restart endpoint', async ({ page }) => {
    let restartCalled = false;
    page.on('dialog', (dialog) => dialog.dismiss());
    page.on('request', (req) => {
      if (req.url().includes('/admin/system_status/restart_server')) restartCalled = true;
    });

    await page.getByRole('button', { name: /initiate application reload/i }).click();
    await page.waitForTimeout(1000);
    expect(restartCalled).toBe(false);
  });

  // NOTE: this genuinely restarts the live Puma dev server (it touches
  // tmp/restart.txt, and this Puma instance is configured to watch and
  // restart on that file). It intentionally runs LAST in this file so no
  // later test in this spec has to deal with the ~10-15s server bounce.
  test('"Initiate Application Reload" prompts for confirmation and, once confirmed, calls the real restart endpoint', async ({ page }) => {
    let confirmMessageSeen = null;
    page.on('dialog', (dialog) => {
      confirmMessageSeen = dialog.message();
      dialog.accept();
    });

    const [response] = await Promise.all([
      page.waitForResponse((res) => res.url().includes('/admin/system_status/restart_server')),
      page.getByRole('button', { name: /initiate application reload/i }).click(),
    ]);

    expect(confirmMessageSeen).toMatch(/rolling soft reload/i);
    expect(response.ok()).toBeTruthy();
    await expect(page.getByText(/restart trigger/i)).toBeVisible({ timeout: 10_000 });

    // The dev Puma process genuinely restarts (~10-15s) after this trigger
    // (it watches tmp/restart.txt). When this spec runs alongside other e2e
    // spec files in the same suite invocation, wait here until the server
    // is back up so later files/tests don't hit ERR_CONNECTION_REFUSED
    // mid-restart.
    await expect(async () => {
      const res = await page.request.get('/users/sign_in', { maxRedirects: 0 }).catch(() => null);
      expect(res).not.toBeNull();
    }).toPass({ timeout: 30_000, intervals: [1000] });
  });
});
