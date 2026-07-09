// E2E regression coverage for the "Edit Image" button in AssetViewer.
//
// Bug: the Studio Editor canvas built its image `src` as
// `${asset.url}?v=${asset.version}`, hardcoding a literal `?`. But
// `asset.url` returned by the backend (via AssetUrlHelper#asset_url_for)
// already includes a `?version_id=...` query string whenever the asset has
// an active version — which is essentially always. The result was a
// malformed double-`?` URL (e.g. `/api/v1/assets/local/<uuid>?version_id=1?v=2`)
// that 404'd, so the Studio Editor opened with a broken/blank canvas.
//
// Fixed in ImageEditorDialog.jsx by appending the cache-busting `v` param
// with `&` whenever the URL already contains a `?`.
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

function mockEmptyFolderContents(page) {
    return page.route('**/api/v1/folders/**', (route) => {
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
}

// Mirrors what the backend actually returns for a normal asset with an
// active version: `url`/`preview_url` always carry a `?version_id=...` query
// string (see AssetUrlHelper#asset_url_for / #local_asset_delivery_path_for).
async function mockViewerAsset(page) {
    await page.route('**/api/v1/assets/edit-image-asset-1', async (route) => {
        route.fulfill({
            status: 200,
            contentType: 'application/json',
            body: JSON.stringify({
                id: 'edit-image-asset-1', uuid: 'edit-image-asset-1', title: 'Edit Image Asset.png',
                status: 'ready',
                version: 3,
                properties: { content_type: 'image/png', file_size: 512_000 },
                metadata: { content_type: 'image/png', file_size: 512_000 },
                content_type: 'image/png',
                size: 512_000,
                folder_id: 'folder-10',
                url: '/api/v1/assets/local/edit-image-asset-1?version_id=9',
                preview_url: '/api/v1/assets/local/edit-image-asset-1?version_id=9',
                editable: true,
            }),
        });
    });
    // Only respond 200 for the well-formed (single `?`) URL. If the frontend
    // regresses to concatenating a second literal `?`, the request URL won't
    // match this route and Playwright will surface a 404 from the app
    // (no other route/backend serves the malformed path in dev/test).
    await page.route('**/api/v1/assets/local/edit-image-asset-1?version_id=9&v=*', (route) => {
        route.fulfill({
            status: 200,
            contentType: 'image/png',
            // 1x1 transparent PNG
            body: Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=', 'base64'),
        });
    });
}

test.describe('AssetViewer — Edit Image opens Studio Editor with a valid image URL', () => {
    test.beforeEach(async ({ page }) => {
        await login(page);
        await mockEmptyFolderContents(page);
        await mockViewerAsset(page);
        await page.goto('/folders?folder=folder-10&id=edit-image-asset-1');
        await page.waitForLoadState('networkidle');
        await expect(page.getByRole('banner').getByText('Edit Image Asset.png')).toBeVisible();
    });

    test('clicking Edit Image opens the Studio Editor and loads the canvas image without a 404', async ({ page }) => {
        const badRequests = [];
        page.on('response', (res) => {
            if (res.url().includes('/api/v1/assets/local/edit-image-asset-1') && res.status() >= 400) {
                badRequests.push(`${res.status()} ${res.url()}`);
            }
        });

        await page.getByRole('button', { name: /Edit Image/i }).click();

        await expect(page.getByText('Studio Editor')).toBeVisible({ timeout: 5_000 });

        const canvasImage = page.getByAltText('Editor Canvas');
        await expect(canvasImage).toBeVisible();

        // The `src` must have a well-formed single `?` followed by `&`-joined
        // params — never a second literal `?`.
        const src = await canvasImage.getAttribute('src');
        expect(src).toBe('/api/v1/assets/local/edit-image-asset-1?version_id=9&v=3');
        expect(src.match(/\?/g)?.length).toBe(1);

        expect(badRequests).toEqual([]);
    });
});
