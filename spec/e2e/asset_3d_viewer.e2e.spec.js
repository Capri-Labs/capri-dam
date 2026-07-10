// E2E coverage for the interactive 3D asset viewer feature:
//
//  1. A GLB asset opened in the Asset Viewer renders the `<model-viewer>`
//     web component (camera-controls enabled) instead of the flat `<img>`
//     preview, and the Reset / Fullscreen controls are present and
//     clickable.
//  2. A USDZ asset — a format with no in-page WebGL renderer — shows the
//     "Download Original" fallback instead of a broken/blank viewer.
//
// All backend responses are mocked via route interception so this test is
// deterministic and doesn't depend on live seed data or a real GLB binary
// actually rendering via WebGL (which isn't reliable/necessary to assert
// in a headless E2E run — the DOM branch-selection + control wiring is
// what we're covering here).
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

function mockAsset(page, { id, title, contentType, size }) {
    return page.route(`**/api/v1/assets/${id}`, async (route) => {
        route.fulfill({
            status: 200,
            contentType: 'application/json',
            body: JSON.stringify({
                id, uuid: id, title, status: 'ready',
                properties: {
                    content_type: contentType, file_size: size,
                    format: '3D Model', model_3d_renderable: contentType !== 'model/vnd.usdz+zip',
                },
                metadata: { content_type: contentType, file_size: size },
                content_type: contentType,
                size,
                folder_id: 'folder-9',
                url: `/api/v1/assets/local/${id}`,
                preview_url: `/api/v1/assets/local/${id}`,
                editable: false,
            }),
        });
    });
}

function mockAssetBinary(page, id, contentType) {
    return page.route(`**/api/v1/assets/local/${id}**`, (route) => {
        route.fulfill({
            status: 200,
            contentType,
            body: Buffer.from('fake-3d-model-binary-fixture'),
        });
    });
}

test.describe('AssetViewer — interactive 3D model preview', () => {
    test.beforeEach(async ({ page }) => {
        await login(page);
        await mockEmptyFolderContents(page);
    });

    test('a GLB asset renders the interactive <model-viewer> with Reset/Fullscreen controls (not the flat image preview)', async ({ page }) => {
        await mockAsset(page, { id: 'glb-asset-1', title: 'Product Hero.glb', contentType: 'model/gltf-binary', size: 4_000_000 });
        await mockAssetBinary(page, 'glb-asset-1', 'model/gltf-binary');

        const requestedGlbUrls = [];
        page.on('request', (req) => { if (req.url().includes('glb-asset-1')) requestedGlbUrls.push(req.url()); });

        await page.goto('/folders?folder=folder-9&id=glb-asset-1');
        await page.waitForLoadState('networkidle');
        await expect(page.getByRole('banner').getByText('Product Hero.glb')).toBeVisible();

        const viewer = page.getByTestId('asset-3d-viewer');
        await expect(viewer).toBeVisible();

        const modelViewer = page.getByTestId('asset-3d-model-viewer');
        await expect(modelViewer).toBeVisible();
        await expect(modelViewer).toHaveAttribute('camera-controls', 'true');
        // The fixture body isn't a real GLB binary, so the real <model-viewer>
        // element clears its own `src` attribute once loading fails — assert
        // against the network request it issued instead of the (transient)
        // DOM attribute.
        expect(requestedGlbUrls.some((url) => url.includes('glb-asset-1'))).toBe(true);

        // No flat <img> fallback for the preview — the 3D viewer replaces it.
        await expect(page.locator('img[src*="glb-asset-1"]')).toHaveCount(0);

        await expect(page.getByTestId('asset-3d-reset-button')).toBeVisible();
        await page.getByTestId('asset-3d-reset-button').click();

        await expect(page.getByTestId('asset-3d-fullscreen-button')).toBeVisible();
        await page.getByTestId('asset-3d-fullscreen-button').click();
    });

    test('a USDZ asset shows the Download Original fallback instead of a broken viewer', async ({ page }) => {
        await mockAsset(page, { id: 'usdz-asset-1', title: 'AR Model.usdz', contentType: 'model/vnd.usdz+zip', size: 2_000_000 });
        await mockAssetBinary(page, 'usdz-asset-1', 'model/vnd.usdz+zip');

        await page.goto('/folders?folder=folder-9&id=usdz-asset-1');
        await page.waitForLoadState('networkidle');
        await expect(page.getByRole('banner').getByText('AR Model.usdz')).toBeVisible();

        await expect(page.getByTestId('asset-3d-viewer')).toHaveCount(0);
        await expect(page.getByTestId('asset-3d-model-viewer')).toHaveCount(0);

        const fallback = page.getByTestId('asset-3d-viewer-download-fallback');
        await expect(fallback).toBeVisible();
        await expect(fallback).toHaveAttribute('href', /usdz-asset-1/);
        await expect(page.getByText(/AR Quick Look/i)).toBeVisible();
    });
});
