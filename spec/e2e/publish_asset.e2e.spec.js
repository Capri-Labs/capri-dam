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
        name: 'publish-e2e.txt',
        mimeType: 'text/plain',
        buffer: Buffer.from('Publish e2e fixture content'),
      },
      title,
      ...(folderId ? { folder_id: String(folderId) } : {}),
    },
    headers: { 'X-CSRF-Token': csrfToken || '' },
  });
  expect(response.ok()).toBeTruthy();
  return response.json();
}

// See copy_folder_asset.e2e.spec.js — the Explorer grid keys off the numeric
// primary key, not the upload response's UUID, so look it up by title.
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

// See copy_folder_asset.e2e.spec.js for why the retry-with-reload wrapper
// exists (first-load JS parse can outrace a just-created fixture).
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

test.describe('Manage Publish — direct publish/unpublish', () => {
  let createdFolderIds = [];
  let createdAssetIds = [];

  test.beforeEach(async ({ page }) => {
    createdFolderIds = [];
    createdAssetIds = [];
    await login(page);
  });

  test.afterEach(async ({ page }) => {
    for (const id of [ ...createdAssetIds ].reverse()) {
      await purgeAsset(page, id);
    }
    for (const id of [ ...createdFolderIds ].reverse()) {
      await purgeFolder(page, id);
    }
  });

  test('publishes then unpublishes a selected asset immediately via the Manage Publish menu', async ({ page }) => {
    const folderName = uniqueName('E2E Publish Folder');
    const folder = await createFolderViaApi(page, folderName);
    createdFolderIds.push(folder.id);

    const assetTitle = uniqueName('E2E Publish Asset');
    await uploadAssetViaApi(page, folder.id, assetTitle);
    const assetId = await getAssetGridId(page, folder.id, assetTitle);
    createdAssetIds.push(assetId);

    await page.goto(`/folders?folder=${folder.id}`);
    await page.waitForLoadState('networkidle');

    const assetItem = page.getByTestId(`asset-grid-item-${assetId}`);
    await waitForCardWithReload(page, assetItem);
    await assetItem.getByRole('checkbox').click({ force: true });

    // "Manage Publish" sits next to (not inside) Tools, and is only offered
    // for an all-assets selection.
    const manageButton = page.getByTestId('manage-publish-button');
    await expect(manageButton).toBeVisible();
    await manageButton.click();

    await Promise.all([
      page.waitForResponse((res) => res.url().includes(`/api/v1/assets/${assetId}/publish`) && res.request().method() === 'POST'),
      page.getByTestId('publish-menu-publish').click(),
    ]);

    const afterPublish = await page.request.get(`/api/v1/assets/${assetId}`);
    expect(afterPublish.ok()).toBeTruthy();
    expect((await afterPublish.json()).published).toBe(true);

    // Re-select (the grid reloads after the action) and unpublish.
    await page.waitForLoadState('networkidle');
    const assetItemAfter = page.getByTestId(`asset-grid-item-${assetId}`);
    await waitForCardWithReload(page, assetItemAfter);
    await assetItemAfter.getByRole('checkbox').click({ force: true });

    await page.getByTestId('manage-publish-button').click();
    await Promise.all([
      page.waitForResponse((res) => res.url().includes(`/api/v1/assets/${assetId}/unpublish`) && res.request().method() === 'POST'),
      page.getByTestId('publish-menu-unpublish').click(),
    ]);

    const afterUnpublish = await page.request.get(`/api/v1/assets/${assetId}`);
    expect(afterUnpublish.ok()).toBeTruthy();
    expect((await afterUnpublish.json()).published).toBe(false);
  });

  test('schedules a future publish via "Publish Later" and leaves the asset unpublished until then', async ({ page }) => {
    const folderName = uniqueName('E2E Publish Later Folder');
    const folder = await createFolderViaApi(page, folderName);
    createdFolderIds.push(folder.id);

    const assetTitle = uniqueName('E2E Publish Later Asset');
    await uploadAssetViaApi(page, folder.id, assetTitle);
    const assetId = await getAssetGridId(page, folder.id, assetTitle);
    createdAssetIds.push(assetId);

    await page.goto(`/folders?folder=${folder.id}`);
    await page.waitForLoadState('networkidle');

    const assetItem = page.getByTestId(`asset-grid-item-${assetId}`);
    await waitForCardWithReload(page, assetItem);
    await assetItem.getByRole('checkbox').click({ force: true });

    await page.getByTestId('manage-publish-button').click();
    await page.getByTestId('publish-menu-publish-later').click();

    const dialog = page.getByRole('dialog');
    await expect(dialog).toBeVisible();
    await expect(dialog.getByText(assetTitle)).toBeVisible();

    // Far-future timestamp so the scheduler worker (polling every 5 minutes)
    // has no chance of applying it during this test run.
    const future = new Date(Date.now() + 365 * 24 * 60 * 60 * 1000);
    const localValue = future.toISOString().slice(0, 16);
    await page.getByTestId('publish-dialog-datetime').fill(localValue);

    await Promise.all([
      page.waitForResponse((res) => res.url().includes(`/api/v1/assets/${assetId}/publish`) && res.request().method() === 'POST'),
      page.getByTestId('publish-dialog-submit').click(),
    ]);

    // A scheduled (not-yet-due) request must not flip `published` yet.
    const afterSchedule = await page.request.get(`/api/v1/assets/${assetId}`);
    expect(afterSchedule.ok()).toBeTruthy();
    expect((await afterSchedule.json()).published).toBe(false);
  });

  test('hides the Manage Publish button when a folder is included in the selection', async ({ page }) => {
    const folderName = uniqueName('E2E Publish Mixed Selection Folder');
    const folder = await createFolderViaApi(page, folderName);
    createdFolderIds.push(folder.id);

    const childFolderName = uniqueName('E2E Publish Child Folder');
    const childFolder = await createFolderViaApi(page, childFolderName, folder.id);
    createdFolderIds.push(childFolder.id);

    await page.goto(`/folders?folder=${folder.id}`);
    await page.waitForLoadState('networkidle');

    const folderCard = page.getByTestId(`folder-card-${childFolder.id}`);
    await waitForCardWithReload(page, folderCard);
    await folderCard.getByRole('checkbox').click({ force: true });

    // Publish/Unpublish are asset-only — must not appear for a
    // folder-only (or mixed) selection.
    await expect(page.getByTestId('manage-publish-button')).not.toBeVisible();
  });
});
