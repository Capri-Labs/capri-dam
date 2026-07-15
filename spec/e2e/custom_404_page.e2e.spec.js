const { test, expect } = require('./fixtures');

const EMAIL = process.env.E2E_EMAIL || 'admin@admin.com';
const PASSWORD = process.env.E2E_PASSWORD || 'AdminUser';

// Covers the custom "funny 404" screen that replaces raw Rails diagnostics /
// stack traces whenever a lookup misses — the bug report that prompted this
// feature was a stale `/api/v1/asset_downloads/:id/download` inbox-email
// link (see ApplicationController#render_not_found + ErrorsController).
async function login(page) {
  await page.goto('/');
  const emailInput = page.locator('input[autocomplete="email"]');
  const loginFormVisible = await emailInput.isVisible({ timeout: 5_000 }).catch(() => false);

  if (!loginFormVisible) {
    await page.waitForLoadState('networkidle');
    const signedIn = await page.locator('#header-root').getAttribute('data-signed-in').catch(() => null);
    if (signedIn === 'true') return;
    await page.goto('/users/sign_in');
    const directLoginVisible = await emailInput.isVisible({ timeout: 5_000 }).catch(() => false);
    if (!directLoginVisible) {
      const signedInRetry = await page.locator('#header-root').getAttribute('data-signed-in').catch(() => null);
      if (signedInRetry === 'true') return;
      throw new Error('Login form did not render and no signed-in session was detected.');
    }
  }

  await emailInput.fill(EMAIL);
  await page.fill('input[autocomplete="current-password"]', PASSWORD);

  const [ response ] = await Promise.all([
    page.waitForResponse((res) => res.url().includes('/users/sign_in.json'), { timeout: 15_000 }),
    page.click('button[type="submit"], input[type="submit"]'),
  ]);
  if (!response.ok()) throw new Error(`login failed with status ${response.status()}`);

  await page.waitForURL(/^https?:\/\/[^/]+\/?(\?.*)?$/, { timeout: 15_000 });
  await page.waitForLoadState('networkidle');

  const signedIn = await page.locator('#header-root').getAttribute('data-signed-in');
  if (signedIn !== 'true') {
    await page.reload();
    await page.waitForLoadState('networkidle');
  }
}

test.describe('Custom 404 page', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
  });

  test('shows the illustrated 404 page for a stale asset-download link, instead of a raw error', async ({ page }) => {
    // Simulates exactly the reported bug: an inbox/email download link
    // whose AssetDownload record no longer exists (expired/purged/never
    // belonged to this user).
    await page.goto('/api/v1/asset_downloads/999999999/download');

    await expect(page.getByText("Well, this is embarrassing.")).toBeVisible();
    await expect(page.getByText(/wandered off/)).toBeVisible();
    await expect(page.getByRole('link', { name: 'Back to Dashboard' })).toBeVisible();

    // Must not leak a raw Rails diagnostics page.
    await expect(page.getByText('ActiveRecord::RecordNotFound')).toHaveCount(0);
  });

  test('shows the illustrated 404 page for a completely unknown URL', async ({ page }) => {
    await page.goto('/this/path/does/not/exist/at/all');

    await expect(page.getByText("Well, this is embarrassing.")).toBeVisible();
    await expect(page.getByRole('link', { name: 'Back to Dashboard' })).toBeVisible();
  });

  test('returns a structured JSON 404 body for API fetch requests', async ({ page, request }) => {
    const cookies = await page.context().cookies();
    const cookieHeader = cookies.map((c) => `${c.name}=${c.value}`).join('; ');

    const response = await request.get('/api/v1/asset_downloads/999999999', {
      headers: { Accept: 'application/json', Cookie: cookieHeader },
    });

    expect(response.status()).toBe(404);
    const body = await response.json();
    expect(body).toEqual({ error: 'Resource not found.' });
  });
});
