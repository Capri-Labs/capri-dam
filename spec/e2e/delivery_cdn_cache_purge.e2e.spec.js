// E2E tests for the Delivery & CDN module's cache-purge / metadata-sync
// surface (see docs/product-info/src/14_delivery_and_cdn.adoc, "Test Coverage
// Status" — previously ZERO E2E coverage for "surrogate-key cache purge").
//
// Covers the real "Edge CDN Ops" menu in the Explorer top bar, which POSTs to
// Api::V1::EdgeOperationsController#sync / #purge — these dispatch
// EdgeMetadataSyncWorker/FolderMetadataSyncWorker and CdnInvalidationWorker
// (Sidekiq), returning 202 Accepted immediately. This test verifies the real
// round-trip (request → 202 → success notification), not FFmpeg/CDN-adapter
// internals (those are covered at the unit/worker level, not via the browser).
//
// Prereqs: app running at E2E_BASE_URL with seed data (bin/rails db:seed).

const { test, expect } = require('./fixtures');

const EMAIL = process.env.E2E_EMAIL || 'admin@admin.com';
const PASSWORD = process.env.E2E_PASSWORD || 'AdminUser';

// The "Select All" checkbox in ExplorerTopBar.jsx only renders when the
// current folder view has at least one folder/asset
// (`viewData.folders?.length > 0 || viewData.assets?.length > 0`). A freshly
// seeded CI database has no folders/assets at root, so this suite must
// create its own fixture folder first — mirroring the createFolderViaApi
// pattern used by copy_folder_asset.e2e.spec.js / move_folder_asset.e2e.spec.js.
async function csrfHeaders(page) {
  const token = await page.locator('meta[name="csrf-token"]').getAttribute('content');
  return {
    Accept: 'application/json',
    'Content-Type': 'application/json',
    'X-CSRF-Token': token || '',
  };
}

async function createFolderViaApi(page, name, parentId = 'root') {
  const response = await page.request.post('/api/v1/folders', {
    headers: await csrfHeaders(page),
    data: { folder: { name, parent_id: parentId } },
  });
  expect(response.ok()).toBeTruthy();
  return response.json();
}

function uniqueName(prefix) {
  return `${prefix} ${Date.now()} ${Math.random().toString(36).slice(2, 8)}`;
}

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

test.describe('Delivery & CDN — Edge CDN Ops (cache purge & metadata sync)', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);

    // A freshly seeded database has no folders/assets at root, and the
    // "Select All" checkbox in ExplorerTopBar.jsx only renders when the
    // current view has at least one item — so create a fixture folder
    // first (same pattern as copy_folder_asset.e2e.spec.js).
    await createFolderViaApi(page, uniqueName('Edge CDN Ops fixture'));

    await page.goto('/folders');
    await page.waitForLoadState('networkidle');

    // The "Edge CDN Ops" button (like the rest of the selection-scoped
    // toolbar) only renders once at least one folder/asset is selected —
    // see ExplorerTopBar.jsx `{hasSelection && viewMode === 'active' && (...)}`.
    // Ticking "Select All" selects every visible item in the current folder.
    await page.getByRole('checkbox', { name: /select all/i }).check();
    await page.getByRole('button', { name: /edge cdn ops/i }).waitFor({ state: 'visible' });
  });

  test('"Sync Metadata to CDN" dispatches a real 202-accepted request and shows a success toast', async ({ page }) => {
    await page.getByRole('button', { name: /edge cdn ops/i }).click();

    const [response] = await Promise.all([
      page.waitForResponse((res) => res.url().includes('/api/v1/edge_operations/sync') && res.request().method() === 'POST'),
      page.getByRole('menuitem', { name: /sync metadata to cdn/i }).click(),
    ]);
    expect(response.status()).toBe(202);
    const body = await response.json();
    expect(body.success).toBe(true);

    await expect(page.getByText(/metadata force-sync to edge kv initiated/i)).toBeVisible();
  });

  test('"Purge Edge Cache" dispatches a real 202-accepted request and shows a warning toast', async ({ page }) => {
    await page.getByRole('button', { name: /edge cdn ops/i }).click();

    const [response] = await Promise.all([
      page.waitForResponse((res) => res.url().includes('/api/v1/edge_operations/purge') && res.request().method() === 'POST'),
      page.getByRole('menuitem', { name: /purge edge cache/i }).click(),
    ]);
    expect(response.status()).toBe(202);
    const body = await response.json();
    expect(body.success).toBe(true);

    await expect(page.getByText(/edge cache invalidation queued for selected items/i)).toBeVisible();
  });

  test('purge request payload carries the folders/assets selection shape', async ({ page }) => {
    // Verifies the client actually sends the `{ folders: [...], assets: [...] }`
    // shape `Api::V1::EdgeOperationsController#purge` expects (via route
    // interception), complementing the success-path assertions above.
    let capturedBody = null;
    await page.route('**/api/v1/edge_operations/purge', async (route) => {
      capturedBody = route.request().postDataJSON();
      await route.continue();
    });

    await page.getByRole('button', { name: /edge cdn ops/i }).click();
    const [response] = await Promise.all([
      page.waitForResponse((res) => res.url().includes('/api/v1/edge_operations/purge')),
      page.getByRole('menuitem', { name: /purge edge cache/i }).click(),
    ]);
    expect(response.status()).toBe(202);
    expect(capturedBody).not.toBeNull();
    expect(Array.isArray(capturedBody.folders)).toBe(true);
    expect(Array.isArray(capturedBody.assets)).toBe(true);
  });
});
