const { test, expect } = require('./fixtures');

const EMAIL = process.env.E2E_EMAIL || 'admin@admin.com';
const PASSWORD = process.env.E2E_PASSWORD || 'AdminUser';
const SAMPLE_PNG_BUFFER = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  'base64'
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

  await page.waitForURL(/^https?:\/\/[^/]+\/?(\?.*)?$/, { timeout: 15_000 });
  await page.waitForLoadState('networkidle');

  const signedIn = await page.locator('#header-root').getAttribute('data-signed-in');
  if (signedIn !== 'true') {
    await page.reload();
    await page.waitForLoadState('networkidle');
  }
}

async function mockFoldersWorkspace(page) {
  const assets = Array.from({ length: 6 }, (_, index) => ({
    id: `toggle-asset-${index + 1}`,
    uuid: `toggle-asset-${index + 1}`,
    title: `Toggle Asset ${index + 1}.png`,
    status: 'ready',
    content_type: 'image/png',
    size: 2048,
    url: `/api/v1/assets/local/toggle-asset-${index + 1}`,
    preview_url: `/api/v1/assets/local/toggle-asset-${index + 1}`,
    properties: { content_type: 'image/png', file_size: 2048 },
  }));

  await page.route('**/api/v1/folders/root**', (route) => {
    if (route.request().method() !== 'GET') return route.continue();
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        folders: [ {
          id: 'toggle-folder-1',
          name: 'Toggle Folder',
          asset_count: 1,
          subfolder_count: 0,
          created_at: '2026-01-01T00:00:00Z',
        } ],
        assets,
        breadcrumbs: [ { id: 'root', name: 'Home' } ],
        sort: { field: 'name', direction: 'asc' },
      }),
    });
  });

  await page.route('**/api/v1/assets/local/toggle-asset-*', (route) => {
    route.fulfill({ status: 200, contentType: 'image/png', body: SAMPLE_PNG_BUFFER });
  });
}

async function previewHeight(page, assetId) {
  return page.getByTestId(`asset-grid-preview-${assetId}`).evaluate((node) => node.getBoundingClientRect().height);
}

test.describe('Folders — main browser view toggles', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
    await mockFoldersWorkspace(page);
  });

  test('renders the folders browser in grid view by default', async ({ page }) => {
    await page.goto('/folders');
    await page.waitForLoadState('networkidle');

    await expect(page.getByTestId('asset-grid')).toBeVisible();
    await expect(page.locator('table')).toHaveCount(0);
    await expect(page.locator('[value="grid"]').first()).toHaveAttribute('aria-pressed', 'true');
  });

  test('switches between list and grid views in the main folders browser', async ({ page }) => {
    await page.goto('/folders');
    await page.waitForLoadState('networkidle');

    await expect(page.locator('table')).toHaveCount(0);

    await page.locator('[value="list"]').first().click();
    await expect(page.locator('table')).toBeVisible();

    await page.locator('[value="grid"]').first().click();
    await expect(page.locator('table')).toHaveCount(0);
    await expect(page.getByTestId('asset-grid')).toBeVisible();
  });

  test('changes asset card density between small, medium, and large in grid view', async ({ page }) => {
    await page.goto('/folders');
    await page.waitForLoadState('networkidle');

    const assetId = 'toggle-asset-1';

    await page.locator('[value="small"]').click();
    const smallHeight = await previewHeight(page, assetId);

    await page.locator('[value="medium"]').click();
    const mediumHeight = await previewHeight(page, assetId);

    await page.locator('[value="large"]').click();
    const largeHeight = await previewHeight(page, assetId);

    expect(smallHeight).toBeLessThan(mediumHeight);
    expect(mediumHeight).toBeLessThan(largeHeight);
  });
});
