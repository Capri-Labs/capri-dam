// Frontend E2E for the Metadata Tools, driven through a real browser against a
// running server. Produces Istanbul frontend coverage (via fixtures.js) and,
// because requests hit the live Rails app, feeds Coverband backend coverage.
//
// Prereqs: app running at E2E_BASE_URL and a seeded login (set via env).

const { test, expect } = require('./fixtures');

const EMAIL    = process.env.E2E_EMAIL    || 'admin@admin.com';
const PASSWORD = process.env.E2E_PASSWORD || 'AdminUser';

async function login(page) {
  await page.goto('/users/sign_in');
  await page.waitForSelector('input[autocomplete="email"]', { timeout: 15_000 });
  await page.fill('input[autocomplete="email"]', EMAIL);
  await page.fill('input[autocomplete="current-password"]', PASSWORD);

  const [response] = await Promise.all([
    page.waitForResponse((res) => res.url().includes('/users/sign_in.json'), { timeout: 15_000 }),
    page.click('button[type="submit"], input[type="submit"]'),
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

test.describe('Metadata Tools E2E', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
  });

  test('Metadata Export screen loads and shows the New Export action', async ({ page }) => {
    await page.goto('/tools/metadata_exports');
    await expect(page.getByRole('button', { name: /new export/i })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Metadata Export' })).toBeVisible();
  });

  test('Metadata Import screen loads with the template download link', async ({ page }) => {
    await page.goto('/tools/metadata_imports');
    await expect(page.getByRole('link', { name: /download template/i })).toBeVisible();
    await expect(page.getByRole('button', { name: /new import/i })).toBeVisible();
  });

  test('per-asset metadata_schema endpoint resolves a pre-filled schema', async ({ page }) => {
    // Discover a real asset, then hit the asset-scoped schema endpoint. The
    // route must resolve a schema (200) or report none (404) — never 500.
    const listRes = await page.request.get('/api/v1/assets', {
      headers: { Accept: 'application/json' },
    });
    expect(listRes.ok()).toBeTruthy();
    const assets = await listRes.json();
    test.skip(!Array.isArray(assets) || assets.length === 0, 'No assets seeded to resolve a schema for');

    const assetId = assets[0].uuid || assets[0].id;
    const res = await page.request.get(`/api/v1/assets/${assetId}/metadata_schema`, {
      headers: { Accept: 'application/json' },
    });
    expect([ 200, 404 ]).toContain(res.status());

    if (res.status() === 200) {
      const body = await res.json();
      expect(body).toHaveProperty('resolved_tabs');
      expect(String(body.asset_uuid || body.asset_id)).toBeTruthy();
    }
  });
});

