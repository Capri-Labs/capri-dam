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

  test('Metadata Schemas screen shows manage controls for an admin (metadata_schema_manager?)', async ({ page }) => {
    await page.goto('/tools/metadata_schemas');
    await expect(page.locator('#root')).toHaveAttribute('data-can-manage-schemas', 'true');
    await expect(page.getByText('Schema Library')).toBeVisible();
    await expect(page.getByTestId('new-schema-button')).toBeVisible();
    await expect(page.getByTestId('read-only-banner')).toHaveCount(0);
  });

  test('admin can duplicate a root schema and rename the copy via the schema editor', async ({ page }) => {
    // Ensure there is at least one root schema to duplicate against, via API.
    const listRes = await page.request.get('/api/v1/metadata_schemas', {
      headers: { Accept: 'application/json' },
    });
    expect(listRes.ok()).toBeTruthy();
    const schemas = await listRes.json();
    test.skip(!Array.isArray(schemas) || schemas.length === 0, 'No root metadata schemas seeded');

    const source = schemas[0];

    await page.goto('/tools/metadata_schemas');
    await page.getByText(source.name, { exact: true }).first().click();

    const duplicateButton = page.getByRole('button', { name: /duplicate/i });
    await expect(duplicateButton).toBeVisible();
    await duplicateButton.click();

    // The newly duplicated schema is auto-selected and titled "Copy of <name>".
    await expect(page.getByRole('heading', { name: `Copy of ${source.name}` })).toBeVisible({ timeout: 10_000 });
    // It should show an "Inherits: <source name>" chip (linked, not deep-copied).
    await expect(page.getByTestId('schema-inherits-chip')).toBeVisible();

    // Open the editor and rename the copy.
    await page.getByRole('button', { name: /^edit$/i }).click();
    const nameField = page.getByTestId('schema-editor-name').locator('input');
    await expect(nameField).toBeVisible();
    await nameField.fill(`Custom ${source.name} ${Date.now()}`);
    await page.getByRole('button', { name: /save schema/i }).click();

    // Dialog closes and the renamed schema is now shown in the detail panel.
    await expect(page.getByTestId('schema-editor-name')).toHaveCount(0, { timeout: 10_000 });
  });

  test('asset viewer lets a user edit values for fields inherited from a system schema, but keeps explicit read_only fields locked', async ({ page }) => {
    // Mock a folder with a single asset and an asset-scoped resolved schema
    // where the "Title" field is inherited from the built-in "Default" root
    // schema (editable) and a "Checksum" field is both inherited AND
    // explicitly read_only (must stay locked).
    await page.route('**/api/v1/folders/**', (route) => {
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          folders: [],
          assets: [],
          breadcrumbs: [ { id: 'root', name: 'Home' } ],
          sort: { field: 'created_at', direction: 'desc' },
        }),
      });
    });
    await page.route('**/api/v1/assets/inherited-field-asset-1', (route) => {
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          id: 'inherited-field-asset-1', uuid: 'inherited-field-asset-1',
          title: 'Inherited Field Asset.png', status: 'ready',
          properties: { content_type: 'image/png', file_size: 1024 },
          metadata: { content_type: 'image/png', file_size: 1024 },
          content_type: 'image/png', size: 1024, folder_id: 'folder-9',
          url: '/api/v1/assets/local/inherited-field-asset-1',
          preview_url: '/api/v1/assets/local/inherited-field-asset-1',
          editable: true,
        }),
      });
    });
    await page.route('**/api/v1/assets/local/inherited-field-asset-1**', (route) => {
      route.fulfill({
        status: 200,
        contentType: 'image/png',
        body: Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=', 'base64'),
      });
    });
    await page.route('**/api/v1/assets/inherited-field-asset-1/metadata_schema', (route) => {
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          id: 99, name: 'Image Schema', asset_uuid: 'inherited-field-asset-1',
          resolved_tabs: [
            {
              id: 'basic', name: 'Basic', inherited: true, schema_name: 'Default',
              fields: [
                { id: 'title', label: 'Title', field_type: 'text', map_to_property: 'dc:title', inherited: true, schema_name: 'Default', value: '' },
                { id: 'checksum', label: 'Checksum', field_type: 'text', map_to_property: 'sys:checksum', inherited: true, schema_name: 'Default', read_only: true, value: 'abc123' },
              ],
            },
          ],
        }),
      });
    });

    await page.goto('/folders?folder=folder-9&id=inherited-field-asset-1');
    await page.waitForLoadState('networkidle');
    await expect(page.getByRole('banner').getByText('Inherited Field Asset.png')).toBeVisible();

    // Switch to the "Metadata" tab.
    await page.getByRole('tab', { name: /metadata/i }).click();
    await expect(page.getByText('Image Schema')).toBeVisible();

    // Inherited-but-not-read_only field: editable.
    const titleInput = page.getByLabel(/^Title/);
    await expect(titleInput).toBeEditable();
    await titleInput.fill('My New Title');
    await expect(titleInput).toHaveValue('My New Title');

    // Explicitly read_only field: still locked despite also being inherited.
    const checksumInput = page.getByLabel(/^Checksum/);
    await expect(checksumInput).toBeDisabled();
  });
});


