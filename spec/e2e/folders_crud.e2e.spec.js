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

  const [response] = await Promise.all([
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

async function moveFolderViaApi(page, id, name, parentId) {
  const response = await page.request.patch(`/api/v1/folders/${id}`, {
    headers: await csrfHeaders(page),
    data: { folder: { name, parent_id: parentId } },
  });
  expect(response.ok()).toBeTruthy();
  return response.json();
}

async function purgeFolder(page, id) {
  const headers = await csrfHeaders(page);
  await page.request.post(`/api/v1/folders/${id}/restore`, { headers }).catch(() => null);
  await page.request.delete(`/api/v1/folders/${id}`, { headers }).catch(() => null);
  await page.request.delete(`/api/v1/folders/${id}/permanent`, { headers }).catch(() => null);
}

async function openFolderInfoPanel(page, folderId, folderName) {
  const card = page.getByTestId(`folder-card-${folderId}`);
  await expect(card).toBeVisible({ timeout: 15_000 });
  await expect(card.getByText(folderName, { exact: true })).toBeVisible();
  await card.hover();
  await card.getByTestId(`folder-info-button-${folderId}`).click({ force: true });
  await expect(page.locator('[role="presentation"]').filter({ hasText: 'Folder properties' })).toBeVisible();
}

test.describe('Folders — CRUD coverage', () => {
  let createdFolderIds = [];

  test.beforeEach(async ({ page }) => {
    createdFolderIds = [];
    await login(page);
  });

  test.afterEach(async ({ page }) => {
    for (const id of [ ...createdFolderIds ].reverse()) {
      await purgeFolder(page, id);
    }
  });

  test('creates a new folder from the explorer top bar', async ({ page }) => {
    const folderName = uniqueName('E2E Folder Create');

    await page.goto('/folders');
    await page.waitForLoadState('networkidle');

    await page.getByRole('button', { name: /new folder/i }).click();
    await page.getByLabel(/folder name/i).fill(folderName);

    const [response] = await Promise.all([
      page.waitForResponse((res) => res.url().includes('/api/v1/folders') && res.request().method() === 'POST'),
      page.getByRole('button', { name: /^create$/i }).click(),
    ]);

    const createdFolder = await response.json();
    createdFolderIds.push(createdFolder.id);

    await expect(page.getByTestId(`folder-card-${createdFolder.id}`)).toBeVisible({ timeout: 15_000 });
    await expect(page.getByText(folderName, { exact: true })).toBeVisible();
  });

  test('renames a folder from the info panel and reflects the new name in the grid', async ({ page }) => {
    const originalName = uniqueName('E2E Folder Rename');
    const renamedName = uniqueName('E2E Folder Renamed');
    const folder = await createFolderViaApi(page, originalName);
    createdFolderIds.push(folder.id);

    await page.goto('/folders');
    await page.waitForLoadState('networkidle');
    await openFolderInfoPanel(page, folder.id, originalName);

    const drawer = page.locator('[role="presentation"]').filter({ hasText: 'Folder properties' });
    await drawer.getByRole('button', { name: /^edit$/i }).click();
    const nameInput = drawer.locator('input').first();
    await expect(nameInput).toHaveValue(originalName);
    await nameInput.fill(renamedName);

    await Promise.all([
      page.waitForResponse((res) => res.url().includes(`/api/v1/folders/${folder.id}`) && res.request().method() === 'PATCH'),
      drawer.getByRole('button', { name: /save changes/i }).click(),
    ]);

    await expect(page.getByTestId(`folder-card-${folder.id}`)).toContainText(renamedName);
    await expect(page.getByText(originalName, { exact: true })).toHaveCount(0);
  });

  test('moves a folder to the bin from the main browser and removes it from the active view', async ({ page }) => {
    const folderName = uniqueName('E2E Folder Delete');
    const folder = await createFolderViaApi(page, folderName);
    createdFolderIds.push(folder.id);

    await page.goto('/folders');
    await page.waitForLoadState('networkidle');

    const card = page.getByTestId(`folder-card-${folder.id}`);
    await expect(card).toBeVisible({ timeout: 15_000 });
    await card.getByRole('checkbox').click({ force: true });

    page.once('dialog', (dialog) => dialog.accept());
    await Promise.all([
      page.waitForResponse((res) => res.url().includes(`/api/v1/folders/${folder.id}`) && res.request().method() === 'DELETE'),
      page.getByRole('button', { name: /move to bin/i }).click(),
    ]);

    await expect(page.getByTestId(`folder-card-${folder.id}`)).toHaveCount(0, { timeout: 15_000 });
  });

  test('shows a moved folder under its new parent after the folder parent is changed', async ({ page }) => {
    const destinationName = uniqueName('E2E Folder Destination');
    const sourceName = uniqueName('E2E Folder Source');
    const destination = await createFolderViaApi(page, destinationName);
    const source = await createFolderViaApi(page, sourceName);
    createdFolderIds.push(destination.id, source.id);

    await page.goto('/folders');
    await page.waitForLoadState('networkidle');
    await expect(page.getByTestId(`folder-card-${destination.id}`)).toBeVisible();
    await expect(page.getByTestId(`folder-card-${source.id}`)).toBeVisible();

    await moveFolderViaApi(page, source.id, sourceName, destination.id);

    await page.reload();
    await page.waitForLoadState('networkidle');
    await expect(page.getByTestId(`folder-card-${source.id}`)).toHaveCount(0);

    await page.getByTestId(`folder-card-${destination.id}`).click();
    await page.waitForURL(new RegExp(`/folders\\?folder=${destination.id}`), { timeout: 15_000 });
    await expect(page.getByTestId(`folder-card-${source.id}`)).toBeVisible({ timeout: 15_000 });
    await expect(page.getByTestId(`folder-card-${source.id}`)).toContainText(sourceName);
  });
});
