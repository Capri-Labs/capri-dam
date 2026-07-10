// E2E coverage for the video asset management feature:
//
//  1. An MP4 asset opened in the Asset Viewer renders the native <video>
//     player (poster + controls) — not the flat <img> preview.
//  2. A non-MP4 video with no transcoded rendition yet shows the
//     "transcoding required" fallback with a Download Original action,
//     instead of a broken/blank player.
//  3. In the Folders Card-view grid, a video asset shows its poster with a
//     Play/Pause overlay toggle; clicking Play swaps to an inline preview
//     and does NOT also open the asset viewer (click does not bubble).
//  4. Tools → Asset Configurations → Upload Limits loads the current
//     (default 2 GB) limit and can save a new value.
//
// All backend responses are mocked via route interception so this test is
// deterministic and doesn't depend on live seed data, a real video binary,
// or FFmpeg being installed in this environment.
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

function mockAsset(page, { id, title, contentType, size, videoPosterUrl, videoMp4RenditionUrl }) {
    return page.route(`**/api/v1/assets/${id}`, async (route) => {
        route.fulfill({
            status: 200,
            contentType: 'application/json',
            body: JSON.stringify({
                id, uuid: id, title, status: 'ready',
                properties: { content_type: contentType, file_size: size },
                metadata: { content_type: contentType, file_size: size },
                content_type: contentType,
                size,
                folder_id: 'folder-video-9',
                url: `/api/v1/assets/local/${id}`,
                preview_url: `/api/v1/assets/local/${id}`,
                video_poster_url: videoPosterUrl || null,
                video_mp4_rendition_url: videoMp4RenditionUrl || null,
                editable: false,
            }),
        });
    });
}

function mockAssetBinary(page, id, contentType) {
    return page.route(`**/api/v1/assets/local/${id}**`, (route) => {
        route.fulfill({ status: 200, contentType, body: Buffer.from('fake-video-binary-fixture') });
    });
}

test.describe('AssetViewer — video preview', () => {
    test.beforeEach(async ({ page }) => {
        await login(page);
        await page.route('**/api/v1/folders/**', (route) => {
            route.fulfill({
                status: 200,
                contentType: 'application/json',
                body: JSON.stringify({
                    folders: [], assets: [],
                    breadcrumbs: [{ id: 'root', name: 'Home' }],
                    sort: { field: 'created_at', direction: 'desc' },
                }),
            });
        });
    });

    test('a native MP4 asset renders the <video> player (poster + controls), not a flat <img>', async ({ page }) => {
        await mockAsset(page, {
            id: 'mp4-asset-1', title: 'Product Demo.mp4', contentType: 'video/mp4', size: 8_000_000,
            videoPosterUrl: '/api/v1/assets/local/mp4-asset-1?variant=video_poster',
        });
        await mockAssetBinary(page, 'mp4-asset-1', 'video/mp4');

        await page.goto('/folders?folder=folder-video-9&id=mp4-asset-1');
        await page.waitForLoadState('networkidle');
        await expect(page.getByRole('banner').getByText('Product Demo.mp4')).toBeVisible();

        const player = page.getByTestId('asset-viewer-video-player');
        await expect(player).toBeVisible();
        await expect(player).toHaveAttribute('src', /mp4-asset-1/);
        await expect(player).toHaveAttribute('poster', /video_poster/);

        await expect(page.locator('img[src*="mp4-asset-1"]')).toHaveCount(0);
    });

    test('a non-native video format with no MP4 rendition yet shows the transcoding-required fallback with Download Original', async ({ page }) => {
        await mockAsset(page, {
            id: 'mov-asset-1', title: 'Raw Footage.mov', contentType: 'video/quicktime', size: 12_000_000,
        });
        await mockAssetBinary(page, 'mov-asset-1', 'video/quicktime');

        await page.goto('/folders?folder=folder-video-9&id=mov-asset-1');
        await page.waitForLoadState('networkidle');
        await expect(page.getByRole('banner').getByText('Raw Footage.mov')).toBeVisible();

        await expect(page.getByTestId('asset-viewer-video-player')).toHaveCount(0);
        await expect(page.getByText(/Video preview isn't available for this format yet/i)).toBeVisible();
        await expect(page.getByRole('button', { name: /Download Original/i })).toBeVisible();
    });
});

test.describe('Folders grid (Card view) — video Play/Pause toggle', () => {
    test.beforeEach(async ({ page }) => {
        await login(page);
    });

    test('a video asset shows its poster with a Play toggle; clicking Play plays inline without opening the asset viewer', async ({ page }) => {
        await page.route('**/api/v1/folders/**', (route) => {
            if (route.request().url().includes('/api/v1/folders/root')) {
                route.fulfill({
                    status: 200,
                    contentType: 'application/json',
                    body: JSON.stringify({
                        folders: [],
                        assets: [{
                            id: 'grid-video-1', title: 'Grid Demo.mp4', content_type: 'video/mp4',
                            status: 'published', size: 5_000_000,
                            url: '/api/v1/assets/local/grid-video-1',
                            video_poster_url: '/api/v1/assets/local/grid-video-1?variant=video_poster',
                        }],
                        breadcrumbs: [{ id: 'root', name: 'Home' }],
                        sort: { field: 'created_at', direction: 'desc' },
                    }),
                });
            } else {
                route.continue();
            }
        });
        await page.route('**/api/v1/assets/local/grid-video-1**', (route) => {
            route.fulfill({ status: 200, contentType: 'video/mp4', body: Buffer.from('fake-video-binary-fixture') });
        });

        await page.goto('/folders?folder=root');
        await page.waitForLoadState('networkidle');

        const playToggle = page.getByTestId('asset-grid-video-play-toggle');
        await expect(playToggle).toBeVisible();
        await expect(page.getByTestId('asset-grid-video-preview-playing')).toHaveCount(0);

        await playToggle.click();
        await expect(page.getByTestId('asset-grid-video-preview-playing')).toBeVisible();

        // The asset viewer must NOT have opened as a result of this click.
        await expect(page.getByRole('banner').getByText('Grid Demo.mp4')).toHaveCount(0);
    });
});

test.describe('Tools → Asset Configurations → Upload Limits', () => {
    test.beforeEach(async ({ page }) => {
        await login(page);
    });

    test('loads the current upload size limit and saves an updated value', async ({ page }) => {
        let savedBytes = null;
        await page.route('**/api/v1/upload_limits', (route) => {
            if (route.request().method() === 'GET') {
                route.fulfill({
                    status: 200,
                    contentType: 'application/json',
                    body: JSON.stringify({ max_upload_size_bytes: savedBytes || 2_147_483_648 }),
                });
            } else if (route.request().method() === 'PUT') {
                const body = route.request().postDataJSON();
                savedBytes = body.max_upload_size_bytes;
                route.fulfill({
                    status: 200,
                    contentType: 'application/json',
                    body: JSON.stringify({ max_upload_size_bytes: savedBytes, message: 'Upload size limit saved successfully.' }),
                });
            } else {
                route.continue();
            }
        });

        await page.goto('/tools/asset_configurations');
        await page.waitForLoadState('networkidle');

        await page.getByText('Upload Limits').click();
        await expect(page.getByRole('spinbutton')).toBeVisible();

        const input = page.locator('input[type="number"]').first();
        await expect(input).toHaveValue(/2/);

        await input.fill('5');
        await page.getByRole('button', { name: /Save/i }).click();

        await expect(page.getByText(/saved successfully/i)).toBeVisible();
    });
});
