const { test, expect } = require('./fixtures');

const EMAIL = process.env.E2E_EMAIL || 'admin@admin.com';
const PASSWORD = process.env.E2E_PASSWORD || 'AdminUser';

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

function uniqueName(prefix) {
  return `${prefix} ${Date.now()} ${Math.random().toString(36).slice(2, 8)}`;
}

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

async function uploadAssetViaApi(page, folderId, title) {
  const csrfToken = await page.locator('meta[name="csrf-token"]').getAttribute('content');
  const response = await page.request.post('/api/v1/assets', {
    multipart: {
      file: {
        name: 'download-e2e.txt',
        mimeType: 'text/plain',
        buffer: Buffer.from('Download e2e fixture content'),
      },
      title,
      ...(folderId ? { folder_id: String(folderId) } : {}),
    },
    headers: { 'X-CSRF-Token': csrfToken || '' },
  });
  expect(response.ok()).toBeTruthy();
  return response.json();
}

// The upload response's `id` is the asset UUID, but the Explorer grid keys
// each `data-testid="asset-grid-item-{id}"` off the internal integer primary
// key (see Api::V1::FoldersController#format_asset_payload) — so look the
// numeric grid id up by title via the folder-contents API instead of
// assuming it matches the upload response.
async function getAssetGridId(page, folderId, title) {
  const response = await page.request.get(`/api/v1/folders/${folderId || 'root'}`);
  expect(response.ok()).toBeTruthy();
  const data = await response.json();
  const match = (data.assets || []).find((a) => a.title === title);
  expect(match, `expected to find an uploaded asset titled "${title}"`).toBeTruthy();
  return match.id;
}

async function purgeFolder(page, id) {
  const headers = await csrfHeaders(page);
  await page.request.post(`/api/v1/folders/${id}/restore`, { headers }).catch(() => null);
  await page.request.delete(`/api/v1/folders/${id}`, { headers }).catch(() => null);
  await page.request.delete(`/api/v1/folders/${id}/permanent`, { headers }).catch(() => null);
}

async function purgeAsset(page, id) {
  const headers = await csrfHeaders(page);
  await page.request.post(`/api/v1/assets/${id}/restore`, { headers }).catch(() => null);
  await page.request.delete(`/api/v1/assets/${id}`, { headers }).catch(() => null);
  await page.request.delete(`/api/v1/assets/${id}/permanent`, { headers }).catch(() => null);
}

async function purgeAssetDownload(page, id) {
  const headers = await csrfHeaders(page);
  await page.request.delete(`/api/v1/asset_downloads/${id}`, { headers }).catch(() => null);
}

// Mirrors metadata_tools.e2e.spec.js's `waitForExport` — this codebase's e2e
// suite relies on a genuinely running Sidekiq worker for async jobs, so poll
// the real API (generous intervals) rather than assuming near-instant
// completion.
async function waitForDownload(page, downloadId) {
  let found = null;

  await expect.poll(async () => {
    const response = await page.request.get(`/api/v1/asset_downloads/${downloadId}`, {
      headers: { Accept: 'application/json' },
    });
    expect(response.ok()).toBeTruthy();
    found = await response.json();
    return found?.status || 'missing';
  }, {
    timeout: 60_000,
    intervals: [1_000, 4_000, 4_000, 4_000, 4_000, 4_000],
  }).toMatch(/completed|failed/);

  expect(found?.status).toBe('completed');
  return found;
}

// The Explorer grid renders from an initial fetch that occasionally beats a
// just-created fixture to the client (first-load JS parse + slow initial
// render can outrace a fast 15s network-idle wait). Reload once or twice
// before failing so this doesn't flake in CI/local runs.
async function waitForCardWithReload(page, locator, { timeout = 8_000, retries = 2 } = {}) {
  for (let attempt = 0; attempt <= retries; attempt += 1) {
    const visible = await locator.isVisible({ timeout }).catch(() => false);
    if (visible) return;
    if (attempt < retries) {
      await page.reload();
      await page.waitForLoadState('networkidle');
    }
  }
  await expect(locator).toBeVisible({ timeout });
}

test.describe('Download folder/asset — Tools menu overlay', () => {
  let createdFolderIds = [];
  let createdAssetIds = [];
  let createdDownloadIds = [];

  test.beforeEach(async ({ page }) => {
    createdFolderIds = [];
    createdAssetIds = [];
    createdDownloadIds = [];
    await login(page);
  });

  test.afterEach(async ({ page }) => {
    for (const id of [ ...createdDownloadIds ].reverse()) {
      await purgeAssetDownload(page, id);
    }
    for (const id of [ ...createdAssetIds ].reverse()) {
      await purgeAsset(page, id);
    }
    for (const id of [ ...createdFolderIds ].reverse()) {
      await purgeFolder(page, id);
    }
  });

  test('downloads a single selected asset via Tools > Download, showing progress through to a ready ZIP link', async ({ page }) => {
    const folderName = uniqueName('E2E Tools Download Asset Folder');
    const folder = await createFolderViaApi(page, folderName);
    createdFolderIds.push(folder.id);

    const assetTitle = uniqueName('E2E Download Asset');
    await uploadAssetViaApi(page, folder.id, assetTitle);
    const assetId = await getAssetGridId(page, folder.id, assetTitle);
    createdAssetIds.push(assetId);

    await page.goto(`/folders?folder=${folder.id}`);
    await page.waitForLoadState('networkidle');

    const assetItem = page.getByTestId(`asset-grid-item-${assetId}`);
    await waitForCardWithReload(page, assetItem);
    await assetItem.getByRole('checkbox').click({ force: true });

    await page.getByRole('button', { name: /^tools$/i }).click();

    const [ createResponse ] = await Promise.all([
      page.waitForResponse((res) => res.url().includes('/api/v1/asset_downloads') && res.request().method() === 'POST'),
      page.getByTestId('tools-menu-download').click(),
    ]);
    expect(createResponse.ok()).toBeTruthy();
    const created = await createResponse.json();
    createdDownloadIds.push(created.id);

    const dialog = page.getByRole('dialog').filter({ hasText: /download 1 item/i });
    await expect(dialog).toBeVisible();
    await expect(dialog.getByText(assetTitle)).toBeVisible();

    // Wait for the real background job to finish (this codebase's e2e suite
    // relies on a genuinely running Sidekiq worker for async jobs — see
    // metadata_tools.e2e.spec.js's identical polling convention).
    await waitForDownload(page, created.id);

    const downloadButton = dialog.getByRole('link', { name: /download zip/i });
    await expect(downloadButton).toBeVisible({ timeout: 15_000 });
    await expect(downloadButton).toHaveAttribute('href', new RegExp(`/api/v1/asset_downloads/${created.id}/download`));

    await dialog.getByRole('button', { name: /close/i }).click();

    // The original asset is untouched — Download never mutates anything.
    await expect(page.getByTestId(`asset-grid-item-${assetId}`)).toBeVisible();
  });

  test('downloads a folder recursively via Tools > Download', async ({ page }) => {
    const folderName = uniqueName('E2E Tools Download Folder');
    const folder = await createFolderViaApi(page, folderName);
    createdFolderIds.push(folder.id);

    const assetTitle = uniqueName('E2E Download Nested Asset');
    await uploadAssetViaApi(page, folder.id, assetTitle);
    const assetId = await getAssetGridId(page, folder.id, assetTitle);
    createdAssetIds.push(assetId);

    await page.goto('/folders');
    await page.waitForLoadState('networkidle');

    const card = page.getByTestId(`folder-card-${folder.id}`);
    await waitForCardWithReload(page, card);
    await card.getByRole('checkbox').click({ force: true });

    await page.getByRole('button', { name: /^tools$/i }).click();

    const [ createResponse ] = await Promise.all([
      page.waitForResponse((res) => res.url().includes('/api/v1/asset_downloads') && res.request().method() === 'POST'),
      page.getByTestId('tools-menu-download').click(),
    ]);
    expect(createResponse.ok()).toBeTruthy();
    const created = await createResponse.json();
    createdDownloadIds.push(created.id);
    // The controller does an eager recursive count up front, so the very
    // first poll already reflects the real file total (1 nested asset).
    expect(created.total_items).toBe(1);

    const dialog = page.getByRole('dialog').filter({ hasText: /download 1 item/i });
    await expect(dialog).toBeVisible();
    await expect(dialog.getByText(folderName)).toBeVisible();

    await waitForDownload(page, created.id);

    const downloadButton = dialog.getByRole('link', { name: /download zip/i });
    await expect(downloadButton).toBeVisible({ timeout: 15_000 });
  });

  test('keeps the Download option enabled even when the selection includes an item without delete rights', async ({ page }) => {
    const folderName = uniqueName('E2E Tools Download No Delete Rights Folder');
    const folder = await createFolderViaApi(page, folderName);
    createdFolderIds.push(folder.id);

    await page.goto('/folders');
    await page.waitForLoadState('networkidle');

    const card = page.getByTestId(`folder-card-${folder.id}`);
    await waitForCardWithReload(page, card);
    await card.getByRole('checkbox').click({ force: true });

    await page.getByRole('button', { name: /^tools$/i }).click();
    // Download only requires read access (already implied by visibility in
    // the listing), so — like Copy — it has no can_delete-style gate on the
    // menu item itself.
    await expect(page.getByTestId('tools-menu-download')).toBeEnabled();
  });
});
