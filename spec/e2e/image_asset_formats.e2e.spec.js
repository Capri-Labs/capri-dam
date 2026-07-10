// E2E coverage for expanded image-format support in the Asset Viewer:
//
//  1. A camera RAW file (e.g. Nikon .nef) with no generated preview shows
//     the "Download Original" fallback instead of a broken <img> pointing
//     at the un-renderable raw binary (regression test for the
//     `canPreview` bug fix — previously any `image/*` content type was
//     treated as previewable even without a generated preview).
//  2. A camera RAW file that DOES have a generated preview (e.g. produced
//     by an ImageMagick RAW delegate) renders the flattened preview image
//     normally.
//  3. A proprietary design-tool source file (Adobe XD) — which has no
//     rasterisation path at all — also shows the download fallback.
//
// All backend responses are mocked via route interception so this test is
// deterministic and doesn't depend on ImageMagick RAW delegates or real
// binaries being present in the test environment.
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

function mockAsset(page, { id, title, contentType, format, previewUrl }) {
    return page.route(`**/api/v1/assets/${id}`, async (route) => {
        route.fulfill({
            status: 200,
            contentType: 'application/json',
            body: JSON.stringify({
                id, uuid: id, title, status: 'ready',
                properties: {
                    content_type: contentType, file_size: 2_000_000, format,
                    ...(previewUrl ? { preview_storage_path: 'previews/fake.jpg', preview_content_type: 'image/jpeg' } : {}),
                },
                metadata: { content_type: contentType, file_size: 2_000_000 },
                content_type: contentType,
                size: 2_000_000,
                folder_id: 'folder-image-1',
                url: `/api/v1/assets/local/${id}`,
                preview_url: previewUrl || null,
                editable: false,
            }),
        });
    });
}

function mockAssetBinary(page, id, contentType) {
    return page.route(`**/api/v1/assets/local/${id}**`, (route) => {
        route.fulfill({ status: 200, contentType, body: Buffer.from('fake-binary-fixture') });
    });
}

test.describe('AssetViewer — expanded image format support', () => {
    test.beforeEach(async ({ page }) => {
        await login(page);
        await mockEmptyFolderContents(page);
    });

    test('a camera RAW file with no generated preview shows the Download Original fallback (not a broken image)', async ({ page }) => {
        await mockAsset(page, {
            id: 'raw-asset-1', title: 'DSC_0042.nef', contentType: 'image/x-raw-nikon', format: 'Camera RAW Image',
        });
        await mockAssetBinary(page, 'raw-asset-1', 'image/x-raw-nikon');

        await page.goto('/folders?folder=folder-image-1&id=raw-asset-1');
        await page.waitForLoadState('networkidle');
        await expect(page.getByRole('banner').getByText('DSC_0042.nef')).toBeVisible();

        await expect(page.getByTestId('asset-viewer-preview-image')).toHaveCount(0);

        const fallback = page.getByTestId('asset-preview-download-fallback');
        await expect(fallback).toBeVisible();
        await expect(fallback.getByText(/Preview not available for this file type/i)).toBeVisible();
        await expect(fallback.getByRole('button', { name: /Download Original/i })).toBeVisible();
    });

    test('a camera RAW file with a generated preview renders the flattened preview image', async ({ page }) => {
        await mockAsset(page, {
            id: 'raw-asset-2', title: 'IMG_0099.cr3', contentType: 'image/x-canon-cr3', format: 'Camera RAW Image',
            previewUrl: '/api/v1/assets/local/raw-asset-2/preview',
        });
        await mockAssetBinary(page, 'raw-asset-2', 'image/x-canon-cr3');
        await page.route('**/api/v1/assets/local/raw-asset-2/preview**', (route) => {
            route.fulfill({ status: 200, contentType: 'image/jpeg', body: Buffer.from('fake-jpeg-preview') });
        });

        await page.goto('/folders?folder=folder-image-1&id=raw-asset-2');
        await page.waitForLoadState('networkidle');
        await expect(page.getByRole('banner').getByText('IMG_0099.cr3')).toBeVisible();

        await expect(page.getByTestId('asset-viewer-preview-image')).toBeVisible();
        await expect(page.getByTestId('asset-preview-download-fallback')).toHaveCount(0);
    });

    test('an Adobe XD design-source file shows the Download Original fallback', async ({ page }) => {
        await mockAsset(page, {
            id: 'xd-asset-1', title: 'Homepage.xd', contentType: 'application/vnd.adobe.xd', format: 'Design Source File',
        });
        await mockAssetBinary(page, 'xd-asset-1', 'application/vnd.adobe.xd');

        await page.goto('/folders?folder=folder-image-1&id=xd-asset-1');
        await page.waitForLoadState('networkidle');
        await expect(page.getByRole('banner').getByText('Homepage.xd')).toBeVisible();

        const fallback = page.getByTestId('asset-preview-download-fallback');
        await expect(fallback).toBeVisible();
        await expect(fallback.getByRole('button', { name: /Download Original/i })).toBeVisible();
    });
});
