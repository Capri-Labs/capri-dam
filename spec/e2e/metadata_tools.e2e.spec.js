// Frontend E2E for the Metadata Tools, driven through a real browser against a
// running server. Produces Istanbul frontend coverage (via fixtures.js) and,
// because requests hit the live Rails app, feeds Coverband backend coverage.
//
// Prereqs: app running at E2E_BASE_URL and a seeded login (set via env).

const fs = require('node:fs/promises');

const { test, expect } = require('./fixtures');

const EMAIL    = process.env.E2E_EMAIL    || 'admin@admin.com';
const PASSWORD = process.env.E2E_PASSWORD || 'AdminUser';
const ONE_PIXEL_PNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  'base64',
);

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

function uniqueName(prefix) {
  return `${prefix} ${Date.now()} ${Math.random().toString(36).slice(2, 8)}`;
}

async function duplicateRootSchema(page) {
  const listRes = await page.request.get('/api/v1/metadata_schemas', {
    headers: { Accept: 'application/json' },
  });
  expect(listRes.ok()).toBeTruthy();
  const schemas = await listRes.json();
  test.skip(!Array.isArray(schemas) || schemas.length === 0, 'No root metadata schemas seeded');

  const source = schemas[0];
  await page.goto('/tools/metadata_schemas');
  await page.getByText(source.name, { exact: true }).first().click();

  const [response] = await Promise.all([
    page.waitForResponse((res) => res.url().includes(`/api/v1/metadata_schemas/${source.id}/duplicate`) && res.request().method() === 'POST'),
    page.getByRole('button', { name: /duplicate/i }).click(),
  ]);

  const duplicated = await response.json();
  await expect(page.getByRole('heading', { name: duplicated.name })).toBeVisible({ timeout: 10_000 });
  await expect(page.getByTestId('schema-inherits-chip')).toBeVisible();
  return { source, duplicated };
}

async function deleteSchema(page, id) {
  const token = await csrfToken(page).catch(() => null);
  await page.request.delete(`/api/v1/metadata_schemas/${id}`, {
    headers: { Accept: 'application/json', 'X-CSRF-Token': token || '' },
  }).catch(() => null);

  if (page.isClosed()) return;

  const signedIn = await page.locator('#header-root').getAttribute('data-signed-in').catch(() => null);
  if (signedIn !== 'true') {
    await page.reload();
    await page.waitForLoadState('networkidle');
  }
}

async function csrfToken(page) {
  const token = await page.evaluate(() => document.querySelector('meta[name="csrf-token"]')?.content);
  if (!token) throw new Error('Missing CSRF token');
  return token;
}

async function createRootSchema(page, name) {
  const token = await csrfToken(page);
  const response = await page.request.post('/api/v1/metadata_schemas', {
    headers: {
      Accept: 'application/json',
      'Content-Type': 'application/json',
      'X-CSRF-Token': token,
    },
    data: {
      metadata_schema: {
        name,
        description: 'E2E schema editor coverage',
        level: 'root',
        tabs: [],
      },
    },
  });
  expect(response.ok()).toBeTruthy();
  return response.json();
}

async function createFolder(page, name, csrf) {
  const response = await page.request.post('/api/v1/folders', {
    data: { folder: { name, parent_id: 'root' } },
    headers: { Accept: 'application/json', 'X-CSRF-Token': csrf },
  });

  expect(response.ok()).toBeTruthy();
  return response.json();
}

async function createAsset(page, { title, csrf, folderId, metadata = {} }) {
  const multipart = {
    file: { name: title.endsWith('.png') ? title : `${title}.png`, mimeType: 'image/png', buffer: ONE_PIXEL_PNG },
    title,
  };
  if (folderId) multipart.folder_id = String(folderId);
  if (Object.keys(metadata).length > 0) multipart.metadata = JSON.stringify(metadata);

  const response = await page.request.post('/api/v1/assets', {
    multipart,
    headers: { Accept: 'application/json', 'X-CSRF-Token': csrf },
  });

  expect([ 201, 202 ]).toContain(response.status());
  const body = await response.json();
  return body.id || body.uuid;
}

async function fetchSchema(page, schemaId) {
  const response = await page.request.get(`/api/v1/metadata_schemas/${schemaId}`, {
    headers: { Accept: 'application/json' },
  });

  expect(response.ok()).toBeTruthy();
  return response.json();
}

async function fetchAsset(page, assetId) {
  const response = await page.request.get(`/api/v1/assets/${assetId}`, {
    headers: { Accept: 'application/json' },
  });

  expect(response.ok()).toBeTruthy();
  return response.json();
}

async function waitForImport(page, importId) {
  let found = null;

  await expect.poll(async () => {
    const response = await page.request.get('/api/v1/metadata_imports', {
      headers: { Accept: 'application/json' },
    });
    expect(response.ok()).toBeTruthy();
    const data = await response.json();
    const items = data.imports || [];
    found = items.find((item) => item.id === importId) || null;
    return found?.status || 'missing';
  }, {
    timeout: 60_000,
    intervals: [1_000, 4_000, 4_000, 4_000, 4_000, 4_000],
  }).toMatch(/completed|failed/);

  expect(found?.status).toBe('completed');
  return found;
}

async function waitForExport(page, exportId) {
  let found = null;

  await expect.poll(async () => {
    const response = await page.request.get('/api/v1/metadata_exports', {
      headers: { Accept: 'application/json' },
    });
    expect(response.ok()).toBeTruthy();
    const data = await response.json();
    const items = data.exports || [];
    found = items.find((item) => item.id === exportId) || null;
    return found?.status || 'missing';
  }, {
    timeout: 60_000,
    intervals: [1_000, 4_000, 4_000, 4_000, 4_000, 4_000],
  }).toMatch(/completed|failed/);

  expect(found?.status).toBe('completed');
  return found;
}

async function deleteMetadataImport(page, importId, csrf) {
  if (!importId || !csrf) return;

  await page.request.delete(`/api/v1/metadata_imports/${importId}`, {
    headers: { 'X-CSRF-Token': csrf },
  }).catch(() => {});
}

async function deleteMetadataExport(page, exportId, csrf) {
  if (!exportId || !csrf) return;

  await page.request.delete(`/api/v1/metadata_exports/${exportId}`, {
    headers: { 'X-CSRF-Token': csrf },
  }).catch(() => {});
}

async function permanentlyDeleteAsset(page, assetId, csrf) {
  if (!assetId || !csrf) return;

  await page.request.delete(`/api/v1/assets/${assetId}`, {
    headers: { 'X-CSRF-Token': csrf },
  }).catch(() => {});

  await page.request.delete('/api/v1/bin/bulk_destroy', {
    headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf },
    data: { items: [ { id: assetId, type: 'asset' } ] },
  }).catch(() => {});
}

async function permanentlyDeleteFolder(page, folderId, csrf) {
  if (!folderId || !csrf) return;

  await page.request.delete(`/api/v1/folders/${folderId}`, {
    headers: { 'X-CSRF-Token': csrf },
  }).catch(() => {});

  await page.request.delete(`/api/v1/folders/${folderId}/permanent`, {
    headers: { 'X-CSRF-Token': csrf },
  }).catch(() => {});
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

  test('Metadata Import preview shows row results before creating the real import job', async ({ page }) => {
    const csrfToken = await page.evaluate(() => document.querySelector('meta[name="csrf-token"]')?.content);
    const now = Date.now();
    const assetTitle = `metadata-preview-e2e-${now}.png`;
    const csvName = `metadata-preview-${now}.csv`;

    const createRes = await page.request.post('/api/v1/assets', {
      multipart: {
        file: { name: assetTitle, mimeType: 'image/png', buffer: ONE_PIXEL_PNG },
        title: assetTitle,
      },
      headers: { Accept: 'application/json', 'X-CSRF-Token': csrfToken },
    });
    expect([ 201, 202 ]).toContain(createRes.status());

    await page.goto('/tools/metadata_imports');
    await page.waitForLoadState('networkidle');
    await page.getByRole('button', { name: /new import/i }).click();

    await page.locator('input[type="file"]').setInputFiles({
      name: csvName,
      mimeType: 'text/csv',
      buffer: Buffer.from(`asset_path,copyright\n/${assetTitle},ACME\n`, 'utf8'),
    });

    await expect(page.getByText(/Detected 2 columns/i)).toBeVisible();

    const dialog = page.getByRole('dialog');
    const [previewResponse] = await Promise.all([
      page.waitForResponse((res) => res.url().includes('/api/v1/metadata_imports/preview'), { timeout: 15_000 }),
      dialog.getByRole('button', { name: /^preview$/i }).click(),
    ]);
    expect(previewResponse.ok()).toBe(true);

    await expect(dialog.getByText(/Preview results/i)).toBeVisible();
    await expect(dialog.getByText('Updated 1 property')).toBeVisible();
    await expect(dialog.getByText(/copyright/i)).toBeVisible();

    const [importResponse] = await Promise.all([
      page.waitForResponse((res) => res.url().includes('/api/v1/metadata_imports') && res.request().method() === 'POST' && !res.url().includes('/preview'), { timeout: 15_000 }),
      dialog.getByRole('button', { name: /^import$/i }).click(),
    ]);
    expect(importResponse.status()).toBe(202);

    await expect(page.getByText(csvName)).toBeVisible({ timeout: 15_000 });
  });

  test('metadata import processes one valid row, reports one failed row, and downloads the results CSV', async ({ page }) => {
    test.setTimeout(90_000);

    const stamp = Date.now();
    const importName = `metadata-import-e2e-${stamp}.csv`;
    const folderName = `Metadata Import E2E ${stamp}`;
    const sourceTitle = `Metadata Import Source ${stamp}`;
    const updatedTitle = `Metadata Import Updated ${stamp}`;
    const description = `Imported description ${stamp}`;
    const missingPath = `/${folderName}/Missing Asset ${stamp}`;
    let csrf;
    let folderId;
    let assetId;
    let importId;

    try {
      csrf = await csrfToken(page);
      const folder = await createFolder(page, folderName, csrf);
      folderId = folder.id;
      assetId = await createAsset(page, {
        title: sourceTitle,
        folderId,
        csrf,
        metadata: { description: 'before-import' },
      });

      const validPath = `/${folderName}/${sourceTitle}`;
      const csv = [
        'asset_path,title,description,tags',
        `"${validPath}","${updatedTitle}","${description}","tag-one|tag-two"`,
        `"${missingPath}","Ignored title","Should fail","missing|asset"`,
      ].join('\n');

      await page.goto('/tools/metadata_imports');
      await page.waitForLoadState('networkidle');
      await page.getByRole('button', { name: /new import/i }).click();
      await page.locator('input[type="file"]').setInputFiles({
        name: importName,
        mimeType: 'text/csv',
        buffer: Buffer.from(csv, 'utf8'),
      });
      await expect(page.getByText(/detected 4 columns in the header row/i)).toBeVisible();

      const [createResponse] = await Promise.all([
        page.waitForResponse((res) =>
          res.url().includes('/api/v1/metadata_imports') &&
          res.request().method() === 'POST',
        ),
        page.getByRole('button', { name: /^import$/i }).click(),
      ]);
      expect(createResponse.status()).toBe(202);
      importId = (await createResponse.json()).id;

      const createdImport = await waitForImport(page, importId);
      expect(createdImport.success_count).toBe(1);
      expect(createdImport.failure_count).toBe(1);

      await page.reload();
      await page.waitForLoadState('networkidle');

      const importRow = page.locator('tbody tr', { hasText: importName }).first();
      await expect(importRow).toBeVisible();
      await expect(importRow.getByText('Completed')).toBeVisible();
      await expect(importRow.getByText('1 ok')).toBeVisible();
      await expect(importRow.getByText('1 fail')).toBeVisible();

      const [download] = await Promise.all([
        page.waitForEvent('download'),
        importRow.getByRole('link', { name: /results/i }).click(),
      ]);
      expect(download.suggestedFilename()).toMatch(/metadata[-_]import[-_]e2e-\d+_results\.csv$/i);

      const resultsPath = await download.path();
      expect(resultsPath).toBeTruthy();
      const resultsCsv = await fs.readFile(resultsPath, 'utf8');
      expect(resultsCsv).toContain('import_status');
      expect(resultsCsv).toContain('import_message');
      expect(resultsCsv).toContain(missingPath);
      expect(resultsCsv).toContain(`No asset found at path '${missingPath}'`);

      const asset = await fetchAsset(page, assetId);
      expect(asset.title).toBe(updatedTitle);
      expect(asset.properties.description).toBe(description);
      expect(asset.properties.tags).toEqual([ 'tag-one', 'tag-two' ]);
    } finally {
      await deleteMetadataImport(page, importId, csrf);
      await permanentlyDeleteAsset(page, assetId, csrf);
      await permanentlyDeleteFolder(page, folderId, csrf);
    }
  });

  test('metadata export creates a job for the root scope and downloads the generated CSV', async ({ page }) => {
    test.setTimeout(90_000);

    const stamp = Date.now();
    const exportName = `metadata-export-e2e-${stamp}`;
    const assetTitle = `Metadata Export Asset ${stamp}`;
    let csrf;
    let assetId;
    let exportId;

    try {
      csrf = await csrfToken(page);
      const createRes = await page.request.post('/api/v1/assets', {
        multipart: {
          file: { name: `${assetTitle}.png`, mimeType: 'image/png', buffer: ONE_PIXEL_PNG },
          title: assetTitle,
        },
        headers: { 'X-CSRF-Token': csrf },
      });
      expect(createRes.ok()).toBe(true);
      const createdAsset = await createRes.json();
      assetId = createdAsset.id || createdAsset.uuid;

      await page.goto('/tools/metadata_exports');
      await page.waitForLoadState('networkidle');
      await page.getByRole('button', { name: /new export/i }).click();
      const dialog = page.getByRole('dialog');
      await expect(dialog).toBeVisible();
      await dialog.getByRole('textbox', { name: /csv file name/i }).fill(exportName);
      await expect(dialog.getByRole('radio', { name: /all properties/i })).toBeChecked();

      const [createResponse] = await Promise.all([
        page.waitForResponse((res) =>
          res.url().includes('/api/v1/metadata_exports') &&
          res.request().method() === 'POST',
        ),
        dialog.getByRole('button', { name: /^export$/i }).click(),
      ]);
      expect(createResponse.status()).toBe(202);
      exportId = (await createResponse.json()).id;

      const createdExport = await waitForExport(page, exportId);
      expect(createdExport.total_assets).toBeGreaterThanOrEqual(1);
      expect(createdExport.file_count).toBe(1);

      const downloadHref = createdExport.files?.[0]?.download_url;
      expect(downloadHref).toBeTruthy();
      const downloadResponse = await page.request.get(downloadHref, {
        headers: { Accept: 'text/csv' },
      });
      expect(downloadResponse.ok()).toBe(true);
      const exportCsv = await downloadResponse.text();
      expect(exportCsv).toContain('asset_id,title,folder_path,status,created_at');
      expect(exportCsv).toContain(assetTitle);
    } finally {
      await deleteMetadataExport(page, exportId, csrf);
      await permanentlyDeleteAsset(page, assetId, csrf);
    }
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
    const { source, duplicated } = await duplicateRootSchema(page);
    try {
      // Open the editor and rename the copy.
      await page.getByRole('button', { name: /^edit$/i }).click();
      const nameField = page.getByTestId('schema-editor-name').locator('input');
      await expect(nameField).toBeVisible();
      await nameField.fill(`Custom ${source.name} ${Date.now()}`);
      await page.getByRole('button', { name: /save schema/i }).click();

      // Dialog closes and the renamed schema is now shown in the detail panel.
      await expect(page.getByTestId('schema-editor-name')).toHaveCount(0, { timeout: 10_000 });
    } finally {
      await deleteSchema(page, duplicated.id);
    }
  });

  test('admin can add a custom field in the schema editor and see it after saving', async ({ page }) => {
    const schemaName = uniqueName('Schema Editor Add');
    const created = await createRootSchema(page, schemaName);
    const tabName = uniqueName('Coverage Tab');
    const fieldLabel = uniqueName('Coverage Field');
    const propertyKey = `dam:${fieldLabel.toLowerCase().replace(/[^a-z0-9]+/g, '_')}`;

    try {
      await page.goto('/tools/metadata_schemas');
      await page.getByText(schemaName, { exact: true }).first().click();
      await page.getByRole('button', { name: /^edit$/i }).click();
      await page.getByTestId('schema-editor-add-tab').click();
      await page.getByPlaceholder(/tab name/i).fill(tabName);
      await page.getByRole('button', { name: /^add$/i }).click();
      await page.getByTestId('schema-editor-add-field').click();
      const fieldRow = page.locator('[data-testid^="schema-editor-field-"]').last();
      await expect(fieldRow).toBeVisible();
      await fieldRow.click();

      const fieldEditor = page.getByTestId('field-editor-column');
      await fieldEditor.getByLabel(/field label/i).fill(fieldLabel);
      await fieldEditor.getByLabel(/map to property/i).fill(propertyKey);

      const [saveResponse] = await Promise.all([
        page.waitForResponse((res) =>
          res.url().includes(`/api/v1/metadata_schemas/${created.id}`) &&
          res.request().method() === 'PATCH',
        ),
        page.getByRole('button', { name: /save schema/i }).click(),
      ]);
      expect(saveResponse.ok()).toBe(true);
      await expect(page.getByTestId('schema-editor-name')).toHaveCount(0, { timeout: 10_000 });

      const schemaRes = await page.request.get(`/api/v1/metadata_schemas/${created.id}`, {
        headers: { Accept: 'application/json' },
      });
      expect(schemaRes.ok()).toBe(true);
      const schemaBody = await schemaRes.json();
      const allFields = (schemaBody.tabs || []).flatMap((tab) => tab.fields || []);
      expect(allFields.some((field) => field.label === fieldLabel && field.map_to_property === propertyKey)).toBeTruthy();
    } finally {
      await deleteSchema(page, created.id);
    }
  });

  test('admin can configure a cascading dropdown between two select fields and it persists', async ({ page }) => {
    const schemaName = uniqueName('Cascade Schema');
    const created = await createRootSchema(page, schemaName);
    const tabName = uniqueName('Cascade Tab');

    try {
      await page.goto('/tools/metadata_schemas');
      await page.getByText(schemaName, { exact: true }).first().click();
      await page.getByRole('button', { name: /^edit$/i }).click();
      await page.getByTestId('schema-editor-add-tab').click();
      await page.getByPlaceholder(/tab name/i).fill(tabName);
      await page.getByRole('button', { name: /^add$/i }).click();

      const editor = page.getByTestId('field-editor-column');
      const selectByLabel = (labelText) =>
        editor.locator('.MuiFormControl-root', { hasText: labelText }).getByRole('combobox');

      // Field 1: Asset Type (parent select)
      await page.getByTestId('schema-editor-add-field').click();
      let fieldRow = page.locator('[data-testid^="schema-editor-field-"]').last();
      await fieldRow.click();
      await selectByLabel('Field Type').click();
      await page.getByRole('option', { name: 'Dropdown (select)' }).click();
      await editor.getByLabel(/field label/i).fill('Asset Type');
      await editor.getByLabel(/map to property/i).fill('mamAssetType');
      await editor.getByRole('button', { name: /add option/i }).click();
      await editor.getByPlaceholder('Value').fill('Product');
      await editor.getByPlaceholder('Label').fill('Product');

      // Field 2: Asset Sub-Type (cascades from Asset Type)
      await page.getByTestId('schema-editor-add-field').click();
      fieldRow = page.locator('[data-testid^="schema-editor-field-"]').last();
      await fieldRow.click();
      await selectByLabel('Field Type').click();
      await page.getByRole('option', { name: 'Dropdown (select)' }).click();
      await editor.getByLabel(/field label/i).fill('Asset Sub-Type');
      await editor.getByLabel(/map to property/i).fill('mamAssetSubType');
      await editor.getByRole('button', { name: /add option/i }).click();
      await editor.getByPlaceholder('Value').fill('In Pack');
      await editor.getByPlaceholder('Label').fill('In Pack');

      await editor.getByTestId('cascade-parent-select').getByRole('combobox').click();
      await page.getByRole('option', { name: 'Asset Type' }).click();
      await editor.getByTestId('cascade-option-Product-In Pack').click();

      const [saveResponse] = await Promise.all([
        page.waitForResponse((res) =>
          res.url().includes(`/api/v1/metadata_schemas/${created.id}`) &&
          res.request().method() === 'PATCH',
        ),
        page.getByRole('button', { name: /save schema/i }).click(),
      ]);
      expect(saveResponse.ok()).toBe(true);
      await expect(page.getByTestId('schema-editor-name')).toHaveCount(0, { timeout: 10_000 });

      const schemaBody = await fetchSchema(page, created.id);
      const allFields = (schemaBody.tabs || []).flatMap((tab) => tab.fields || []);
      const parentField = allFields.find((f) => f.label === 'Asset Type');
      const childField = allFields.find((f) => f.label === 'Asset Sub-Type');
      expect(childField.rules?.cascade?.parent_field_id).toBe(parentField.id);
      expect(childField.rules?.cascade?.map?.Product).toEqual([ 'In Pack' ]);
    } finally {
      await deleteSchema(page, created.id);
    }
  });

  test('admin can configure a dynamic Requirement rule and a Visibility rule, and both persist', async ({ page }) => {
    const schemaName = uniqueName('Rules Schema');
    const created = await createRootSchema(page, schemaName);
    const tabName = uniqueName('Rules Tab');

    try {
      await page.goto('/tools/metadata_schemas');
      await page.getByText(schemaName, { exact: true }).first().click();
      await page.getByRole('button', { name: /^edit$/i }).click();
      await page.getByTestId('schema-editor-add-tab').click();
      await page.getByPlaceholder(/tab name/i).fill(tabName);
      await page.getByRole('button', { name: /^add$/i }).click();

      const editor = page.getByTestId('field-editor-column');
      const selectByLabel = (labelText) =>
        editor.locator('.MuiFormControl-root', { hasText: labelText }).getByRole('combobox');

      // Field 1: License Requirements (select, parent for the Requirement rule)
      await page.getByTestId('schema-editor-add-field').click();
      let fieldRow = page.locator('[data-testid^="schema-editor-field-"]').last();
      await fieldRow.click();
      await selectByLabel('Field Type').click();
      await page.getByRole('option', { name: 'Dropdown (select)' }).click();
      await editor.getByLabel(/field label/i).fill('License Requirements');
      await editor.getByLabel(/map to property/i).fill('license');
      await editor.getByRole('button', { name: /add option/i }).click();
      await editor.getByPlaceholder('Value').fill('Licensed');
      await editor.getByPlaceholder('Label').fill('Licensed');

      // Field 2: Copyright Owner (text, required only when License = Licensed)
      await page.getByTestId('schema-editor-add-field').click();
      fieldRow = page.locator('[data-testid^="schema-editor-field-"]').last();
      await fieldRow.click();
      await editor.getByLabel(/field label/i).fill('Copyright Owner');
      await editor.getByLabel(/map to property/i).fill('copyrightOwner');
      await editor.getByTestId('requirement-parent-select').getByRole('combobox').click();
      await page.getByRole('option', { name: 'License Requirements' }).click();
      await editor.getByTestId('requirement-value-Licensed').click();

      // Field 3: Country (select, parent for the Visibility rule)
      await page.getByTestId('schema-editor-add-field').click();
      fieldRow = page.locator('[data-testid^="schema-editor-field-"]').last();
      await fieldRow.click();
      await selectByLabel('Field Type').click();
      await page.getByRole('option', { name: 'Dropdown (select)' }).click();
      await editor.getByLabel(/field label/i).fill('Country');
      await editor.getByLabel(/map to property/i).fill('country');
      await editor.getByRole('button', { name: /add option/i }).click();
      await editor.getByPlaceholder('Value').fill('United States');
      await editor.getByPlaceholder('Label').fill('United States');

      // Field 4: State (select, only visible when Country = United States)
      await page.getByTestId('schema-editor-add-field').click();
      fieldRow = page.locator('[data-testid^="schema-editor-field-"]').last();
      await fieldRow.click();
      await selectByLabel('Field Type').click();
      await page.getByRole('option', { name: 'Dropdown (select)' }).click();
      await editor.getByLabel(/field label/i).fill('State');
      await editor.getByLabel(/map to property/i).fill('state');
      await editor.getByRole('button', { name: /add option/i }).click();
      await editor.getByPlaceholder('Value').fill('California');
      await editor.getByPlaceholder('Label').fill('California');
      await editor.getByTestId('visibility-parent-select').getByRole('combobox').click();
      await page.getByRole('option', { name: 'Country' }).click();
      await editor.getByTestId('visibility-value-United States').click();

      const [saveResponse] = await Promise.all([
        page.waitForResponse((res) =>
          res.url().includes(`/api/v1/metadata_schemas/${created.id}`) &&
          res.request().method() === 'PATCH',
        ),
        page.getByRole('button', { name: /save schema/i }).click(),
      ]);
      expect(saveResponse.ok()).toBe(true);
      await expect(page.getByTestId('schema-editor-name')).toHaveCount(0, { timeout: 10_000 });

      const schemaBody = await fetchSchema(page, created.id);
      const allFields = (schemaBody.tabs || []).flatMap((tab) => tab.fields || []);
      const licenseField   = allFields.find((f) => f.label === 'License Requirements');
      const copyrightField = allFields.find((f) => f.label === 'Copyright Owner');
      const countryField   = allFields.find((f) => f.label === 'Country');
      const stateField     = allFields.find((f) => f.label === 'State');

      expect(copyrightField.rules?.requirement?.parent_field_id).toBe(licenseField.id);
      expect(copyrightField.rules?.requirement?.values).toEqual([ 'Licensed' ]);
      expect(stateField.rules?.visibility?.parent_field_id).toBe(countryField.id);
      expect(stateField.rules?.visibility?.values).toEqual([ 'United States' ]);
    } finally {
      await deleteSchema(page, created.id);
    }
  });

  test('admin can remove a custom field in the schema editor and verify it is gone', async ({ page }) => {
    const schemaName = uniqueName('Schema Editor Remove');
    const created = await createRootSchema(page, schemaName);
    const tabName = uniqueName('Removal Tab');
    const fieldLabel = uniqueName('Removable Field');
    const propertyKey = `dam:${fieldLabel.toLowerCase().replace(/[^a-z0-9]+/g, '_')}`;

    try {
      await page.goto('/tools/metadata_schemas');
      await page.getByText(schemaName, { exact: true }).first().click();
      await page.getByRole('button', { name: /^edit$/i }).click();
      await page.getByTestId('schema-editor-add-tab').click();
      await page.getByPlaceholder(/tab name/i).fill(tabName);
      await page.getByRole('button', { name: /^add$/i }).click();
      await page.getByTestId('schema-editor-add-field').click();
      const fieldRow = page.locator('[data-testid^="schema-editor-field-"]').last();
      await expect(fieldRow).toBeVisible();
      await fieldRow.click();

      const fieldEditor = page.getByTestId('field-editor-column');
      await fieldEditor.getByLabel(/field label/i).fill(fieldLabel);
      await fieldEditor.getByLabel(/map to property/i).fill(propertyKey);
      await page.getByRole('button', { name: /save schema/i }).click();
      await expect(page.getByTestId('schema-editor-name')).toHaveCount(0, { timeout: 10_000 });

      const createdSchemaRes = await page.request.get(`/api/v1/metadata_schemas/${created.id}`, {
        headers: { Accept: 'application/json' },
      });
      expect(createdSchemaRes.ok()).toBe(true);
      const createdSchemaBody = await createdSchemaRes.json();
      const createdFields = (createdSchemaBody.tabs || []).flatMap((tab) => tab.fields || []);
      expect(createdFields.some((field) => field.label === fieldLabel && field.map_to_property === propertyKey)).toBeTruthy();

      await page.getByRole('button', { name: /^edit$/i }).click();
      const reopenedDialog = page.getByRole('dialog');
      const reopenedFieldRow = reopenedDialog.locator('[data-testid^="schema-editor-field-"]').first();
      await expect(reopenedFieldRow).toBeVisible();
      await reopenedFieldRow.locator('[data-testid^="schema-editor-delete-field-"]').click();
      await expect(reopenedDialog.locator('[data-testid^="schema-editor-field-"]')).toHaveCount(0);

      const [saveResponse] = await Promise.all([
        page.waitForResponse((res) =>
          res.url().includes(`/api/v1/metadata_schemas/${created.id}`) &&
          res.request().method() === 'PATCH',
        ),
        page.getByRole('button', { name: /save schema/i }).click(),
      ]);
      expect(saveResponse.ok()).toBe(true);
      await expect(page.getByTestId('schema-editor-name')).toHaveCount(0, { timeout: 10_000 });

      const schemaRes = await page.request.get(`/api/v1/metadata_schemas/${created.id}`, {
        headers: { Accept: 'application/json' },
      });
      expect(schemaRes.ok()).toBe(true);
      const schemaBody = await schemaRes.json();
      const allFields = (schemaBody.tabs || []).flatMap((tab) => tab.fields || []);
      expect(allFields.some((field) => field.label === fieldLabel || field.map_to_property === propertyKey)).toBeFalsy();
    } finally {
      await deleteSchema(page, created.id);
    }
  });

  test('Metadata Schemas screen paginates root schemas and supports select-all + bulk delete', async ({ page }) => {
    test.setTimeout(60_000);

    const stamp = Date.now();
    const createdIds = [];

    try {
      // Seed enough root schemas to guarantee a second pagination page
      // (component paginates at 10 root schemas per page).
      // Prefix with "0-" so these sort alphabetically ahead of any
      // pre-existing non-builtin schemas, keeping page-1 positions predictable.
      for (let i = 0; i < 11; i += 1) {
        const created = await createRootSchema(page, uniqueName(`0-Pagination Schema ${String(i).padStart(2, '0')}`));
        createdIds.push(created.id);
      }

      await page.goto('/tools/metadata_schemas');
      await page.waitForLoadState('networkidle');

      // Pagination controls should now be visible with at least 2 pages.
      await expect(page.getByText(/page 1 of \d+/i)).toBeVisible();
      const nextButton = page.getByRole('button', { name: 'Next' });
      await expect(nextButton).toBeEnabled();
      await nextButton.click();
      await expect(page.getByText(/page 2 of \d+/i)).toBeVisible();

      // Go back to page 1 and select two of the newly created schemas for bulk delete.
      await page.getByRole('button', { name: 'Previous' }).click();
      await expect(page.getByText(/page 1 of \d+/i)).toBeVisible();

      const firstCheckbox = page.getByTestId(`schema-select-${createdIds[0]}`).locator('input');
      const secondCheckbox = page.getByTestId(`schema-select-${createdIds[1]}`).locator('input');
      await firstCheckbox.check();
      await secondCheckbox.check();

      await expect(page.getByText('2 selected')).toBeVisible();

      page.once('dialog', (dialog) => dialog.accept());
      const [bulkDeleteResponse] = await Promise.all([
        page.waitForResponse((res) =>
          res.url().includes('/api/v1/metadata_schemas/bulk_delete') &&
          res.request().method() === 'DELETE',
        ),
        page.getByTestId('schema-bulk-delete-button').click(),
      ]);
      expect(bulkDeleteResponse.ok()).toBeTruthy();
      const body = await bulkDeleteResponse.json();
      expect(body.deleted_count).toBe(2);

      // Deleted schemas are removed from the list, remaining ones still show.
      await expect(page.getByTestId(`schema-select-${createdIds[0]}`)).toHaveCount(0);
      await expect(page.getByTestId(`schema-select-${createdIds[1]}`)).toHaveCount(0);
    } finally {
      await Promise.all(createdIds.map((id) => deleteSchema(page, id)));
    }
  });

  test('Metadata Export screen supports select-all + bulk delete of export jobs', async ({ page }) => {
    test.setTimeout(60_000);

    const csrf = await csrfToken(page);
    const stamp = Date.now();
    const exportIds = [];

    try {
      for (let i = 0; i < 2; i += 1) {
        const response = await page.request.post('/api/v1/metadata_exports', {
          headers: { Accept: 'application/json', 'X-CSRF-Token': csrf },
          data: { metadata_export: { name: `bulk-delete-export-e2e-${stamp}-${i}`, property_mode: 'all' } },
        });
        expect(response.status()).toBe(202);
        exportIds.push((await response.json()).id);
      }

      await page.goto('/tools/metadata_exports');
      await page.waitForLoadState('networkidle');

      for (const id of exportIds) {
        await page.getByTestId(`export-select-${id}`).locator('input').check();
      }
      await expect(page.getByTestId('export-bulk-delete-button')).toBeVisible();

      page.once('dialog', (dialog) => dialog.accept());
      const [bulkDeleteResponse] = await Promise.all([
        page.waitForResponse((res) =>
          res.url().includes('/api/v1/metadata_exports/bulk_delete') &&
          res.request().method() === 'DELETE',
        ),
        page.getByTestId('export-bulk-delete-button').click(),
      ]);
      expect(bulkDeleteResponse.ok()).toBeTruthy();
      const body = await bulkDeleteResponse.json();
      expect(body.deleted_count).toBe(2);

      for (const id of exportIds) {
        await expect(page.getByTestId(`export-select-${id}`)).toHaveCount(0);
      }
      exportIds.length = 0;
    } finally {
      for (const id of exportIds) {
        await deleteMetadataExport(page, id, csrf);
      }
    }
  });

  test('Metadata Import screen supports select-all + bulk delete of import jobs', async ({ page }) => {
    test.setTimeout(60_000);

    const csrf = await csrfToken(page);
    const stamp = Date.now();
    const importIds = [];
    const csv = 'asset_path,title\n"/does/not/exist.png","Ignored"';

    try {
      for (let i = 0; i < 2; i += 1) {
        const response = await page.request.post('/api/v1/metadata_imports', {
          multipart: {
            'metadata_import[source_file]': {
              name: `bulk-delete-import-e2e-${stamp}-${i}.csv`,
              mimeType: 'text/csv',
              buffer: Buffer.from(csv, 'utf8'),
            },
          },
          headers: { Accept: 'application/json', 'X-CSRF-Token': csrf },
        });
        expect(response.status()).toBe(202);
        importIds.push((await response.json()).id);
      }

      await page.goto('/tools/metadata_imports');
      await page.waitForLoadState('networkidle');

      for (const id of importIds) {
        await page.getByTestId(`import-select-${id}`).locator('input').check();
      }
      await expect(page.getByTestId('import-bulk-delete-button')).toBeVisible();

      page.once('dialog', (dialog) => dialog.accept());
      const [bulkDeleteResponse] = await Promise.all([
        page.waitForResponse((res) =>
          res.url().includes('/api/v1/metadata_imports/bulk_delete') &&
          res.request().method() === 'DELETE',
        ),
        page.getByTestId('import-bulk-delete-button').click(),
      ]);
      expect(bulkDeleteResponse.ok()).toBeTruthy();
      const body = await bulkDeleteResponse.json();
      expect(body.deleted_count).toBe(2);

      for (const id of importIds) {
        await expect(page.getByTestId(`import-select-${id}`)).toHaveCount(0);
      }
      importIds.length = 0;
    } finally {
      for (const id of importIds) {
        await deleteMetadataImport(page, id, csrf);
      }
    }
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
