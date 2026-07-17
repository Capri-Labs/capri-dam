// E2E tests for the Delivery & CDN module's CDN-provider configuration
// surface (System Status → Storage & Edge → Edge CDN sub-tab), extending
// `cdn_image_optimizer_formats.e2e.spec.js` (Fastly-only) to cover the
// Cloudflare and Akamai providers — see
// docs/product-info/src/99_roadmap_and_test_coverage.adoc, "System
// Operations & Admin" row: "Storage & Edge save flow is covered only for the
// Fastly provider — Cloudflare/Akamai provider switch is still untested."
//
// Covers:
//  - Switching the "Target Edge Provider" dropdown to Cloudflare/Akamai
//    reveals the correct provider-specific credential fields.
//  - Saving each provider's settings round-trips through the real
//    PUT /api/v1/cdn_configurations call and persists across a reload.
//
// Prereqs: app running at E2E_BASE_URL with seed data (bin/rails db:seed).

const { test, expect } = require('./fixtures');

const EMAIL = process.env.E2E_EMAIL || 'admin@admin.com';
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
  expect(response.ok()).toBeTruthy();

  await page.waitForURL(/^https?:\/\/[^/]+\/?(\?.*)?$/, { timeout: 15_000 });
  await page.waitForLoadState('networkidle');

  const signedIn = await page.locator('#header-root').getAttribute('data-signed-in');
  if (signedIn !== 'true') {
    await page.reload();
    await page.waitForLoadState('networkidle');
  }
}

async function gotoEdgeCdnTab(page) {
  await page.goto('/settings/system');
  await page.waitForLoadState('networkidle');
  await page.getByRole('tab', { name: /storage & edge/i }).click();
  await page.getByRole('tab', { name: /edge cdn/i }).click();
}

async function selectProvider(page, providerLabel) {
  // The MUI <InputLabel>/<Select> pair here isn't wired with matching
  // labelId/id, so the accessible name association getByLabel() relies on
  // doesn't hold — target the combobox via its containing FormControl text
  // instead (mirrors the actual rendered DOM, verified via Playwright trace).
  await page.locator('.MuiFormControl-root').filter({ hasText: 'Target Edge Provider' })
    .getByRole('combobox').click();
  await page.getByRole('option', { name: providerLabel }).click();
}

test.describe('Admin — Storage & Edge — Edge CDN — Cloudflare/Akamai provider switch', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
    await gotoEdgeCdnTab(page);
  });

  // Only one CDN provider can be `is_active` at a time
  // (CdnConfiguration#ensure_single_active_provider), and this environment's
  // seed data assumes Fastly is active (relied on by
  // cdn_image_optimizer_formats.e2e.spec.js). The "saving persists" tests
  // below activate Cloudflare/Akamai to prove the save round-trip — restore
  // Fastly as active afterwards so this spec doesn't leak state into other
  // Edge CDN specs.
  test.afterEach(async ({ page }) => {
    const token = await page.locator('meta[name="csrf-token"]').getAttribute('content');
    await page.request.put('/api/v1/cdn_configurations', {
      headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': token || '' },
      data: { provider: 'fastly', is_active: true, settings: {} },
    }).catch(() => null);
  });

  test('switching to Cloudflare reveals its credential fields', async ({ page }) => {
    await selectProvider(page, 'Cloudflare Enterprise');

    await expect(page.getByText('cloudflare Credentials', { exact: false })).toBeVisible();
    await expect(page.getByLabel('Zone ID')).toBeVisible();
    await expect(page.getByLabel(/workers kv namespace id/i)).toBeVisible();
    await expect(page.getByLabel('API Token')).toBeVisible();

    // Fastly-only fields must not leak into the Cloudflare form.
    await expect(page.getByLabel('Service ID')).not.toBeVisible();
  });

  test('switching to Akamai reveals its credential fields', async ({ page }) => {
    await selectProvider(page, 'Akamai Edge');

    await expect(page.getByText('akamai Credentials', { exact: false })).toBeVisible();
    await expect(page.getByLabel('Host (URL)')).toBeVisible();
    await expect(page.getByLabel('EdgeKV Namespace')).toBeVisible();
    await expect(page.getByLabel('Client Secret')).toBeVisible();
  });

  test('saving Cloudflare settings persists via the real API and survives a reload', async ({ page }) => {
    await selectProvider(page, 'Cloudflare Enterprise');

    const zoneId = `zone-${Date.now()}`;
    await page.getByLabel('Zone ID').fill(zoneId);
    await page.getByLabel(/workers kv namespace id/i).fill(`kv-${Date.now()}`);
    await page.getByLabel('API Token').fill('test-cf-token');

    const [response] = await Promise.all([
      page.waitForResponse((res) => res.url().includes('/api/v1/cdn_configurations') && res.request().method() === 'PUT'),
      page.getByRole('button', { name: /save cdn settings/i }).click(),
    ]);
    expect(response.ok()).toBeTruthy();
    const body = await response.json();
    expect(body.success).toBe(true);

    await expect(page.getByText(/cloudflare configuration updated/i)).toBeVisible();

    // The #index action masks every non-whitelisted settings value (all
    // fields here are treated as secrets, not just API tokens) to
    // `••••••••<last 4 chars>` — see CdnConfigurationsController#format_config
    // / NON_SECRET_SETTINGS_KEYS. Confirm persistence via that masked
    // fingerprint rather than the raw value, which is intentionally never
    // returned again after being saved.
    await page.reload();
    await page.waitForLoadState('networkidle');
    await gotoEdgeCdnTab(page);
    await selectProvider(page, 'Cloudflare Enterprise');
    await expect(page.getByLabel('Zone ID')).toHaveValue(`••••••••${zoneId.slice(-4)}`);
  });

  test('saving Akamai settings persists via the real API and survives a reload', async ({ page }) => {
    await selectProvider(page, 'Akamai Edge');

    const host = `akamai-${Date.now()}.example.net`;
    await page.getByLabel('Host (URL)').fill(host);
    await page.getByLabel('EdgeKV Namespace').fill(`edgekv-${Date.now()}`);
    await page.getByLabel('Client Secret').fill('test-akamai-secret');

    const [response] = await Promise.all([
      page.waitForResponse((res) => res.url().includes('/api/v1/cdn_configurations') && res.request().method() === 'PUT'),
      page.getByRole('button', { name: /save cdn settings/i }).click(),
    ]);
    expect(response.ok()).toBeTruthy();
    const body = await response.json();
    expect(body.success).toBe(true);

    await expect(page.getByText(/akamai configuration updated/i)).toBeVisible();

    // See the masking note above — Host is not in NON_SECRET_SETTINGS_KEYS,
    // so it round-trips as a masked fingerprint too.
    await page.reload();
    await page.waitForLoadState('networkidle');
    await gotoEdgeCdnTab(page);
    await selectProvider(page, 'Akamai Edge');
    await expect(page.getByLabel('Host (URL)')).toHaveValue(`••••••••${host.slice(-4)}`);
  });
});
