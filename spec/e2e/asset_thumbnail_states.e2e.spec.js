// E2E coverage for the AssetGrid thumbnail states introduced to replace
// broken <img> tags with a graceful UX:
//
//   1. "Processing…" placeholder — shown for assets whose background worker
//      (AssetProcessorWorker) hasn't finished yet (status: pending/processing).
//      No image request is attempted at all for these assets.
//   2. "Preview unavailable" fallback — shown when a ready asset's preview
//      URL fails to load (e.g. storage drift, missing file on disk).
//
// Both states are simulated here via route interception rather than relying
// on real broken/pending seed data, so the test is deterministic and does
// not depend on background worker timing.
//
// Runs against a live Rails server (set E2E_BASE_URL, E2E_EMAIL, E2E_PASSWORD).

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

    await page.waitForURL(/^https?:\/\/[^/]+\/?(\?.*)?$/, { timeout: 15_000 });
    await page.waitForLoadState('networkidle');
}

function baseAsset(overrides = {}) {
    return {
        id: 'a1',
        uuid: 'a1',
        title: 'Sample.jpg',
        name: 'Sample.jpg',
        status: 'ready',
        version: 1,
        properties: { content_type: 'image/jpeg', size: 12345 },
        size: 12345,
        content_type: 'image/jpeg',
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
        url: '/api/v1/assets/local/a1',
        preview_url: '/api/v1/assets/local/a1',
        editable: true,
        ...overrides,
    };
}

function mockFolderContents(page, assets) {
    return page.route('**/api/v1/folders/root**', (route) => {
        route.fulfill({
            status: 200,
            contentType: 'application/json',
            body: JSON.stringify({
                folders: [],
                assets,
                breadcrumbs: [ { id: 'root', name: 'Home' } ],
                sort: { field: 'created_at', direction: 'desc' },
            }),
        });
    });
}

test.describe('AssetGrid thumbnail states', () => {
    test.beforeEach(async ({ page }) => { await login(page); });

    test('shows a "Processing…" placeholder for pending/processing assets without requesting an image', async ({ page }) => {
        const requestedUrls = [];
        page.on('request', (req) => {
            if (req.url().includes('/api/v1/assets/local/')) requestedUrls.push(req.url());
        });

        await mockFolderContents(page, [
            baseAsset({ id: 'pending-1', uuid: 'pending-1', title: 'Pending.jpg', status: 'pending', url: '/api/v1/assets/local/pending-1', preview_url: '/api/v1/assets/local/pending-1' }),
            baseAsset({ id: 'processing-1', uuid: 'processing-1', title: 'Processing.jpg', status: 'processing', url: '/api/v1/assets/local/processing-1', preview_url: '/api/v1/assets/local/processing-1' }),
        ]);

        await page.goto('/folders');
        await page.waitForLoadState('networkidle');

        await expect(page.getByText(/processing/i).first()).toBeVisible();

        // No thumbnail <img> request should ever be attempted for a
        // processing/pending asset — the UI must short-circuit before
        // attempting to load a URL that is guaranteed to 404.
        expect(requestedUrls.filter((u) => u.includes('pending-1') || u.includes('processing-1'))).toHaveLength(0);
    });

    test('shows a "Preview unavailable" fallback when a ready asset\'s image fails to load', async ({ page }) => {
        await mockFolderContents(page, [
            baseAsset({ id: 'broken-1', uuid: 'broken-1', title: 'Broken.jpg', status: 'ready', url: '/api/v1/assets/local/broken-1', preview_url: '/api/v1/assets/local/broken-1' }),
        ]);

        // Force the thumbnail image request to fail, simulating a missing
        // file on disk / storage drift.
        await page.route('**/api/v1/assets/local/broken-1**', (route) => {
            route.fulfill({ status: 404, contentType: 'text/plain', body: 'not found' });
        });

        await page.goto('/folders');
        await page.waitForLoadState('networkidle');

        await expect(page.getByText(/preview unavailable/i)).toBeVisible({ timeout: 15_000 });
    });
});
