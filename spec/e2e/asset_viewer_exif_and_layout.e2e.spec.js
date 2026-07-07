// E2E coverage for two AssetViewer UX fixes:
//
//  1. The "EXIF / IPTC / XMP Data" block in the Info tab is collapsed by
//     default (previously it was always expanded, dumping a large raw JSON
//     blob into view). Clicking the header expands/collapses it.
//  2. The left-hand image preview pane must stay pixel-stable (fixed
//     width/position) when switching between the right-hand inspector tabs
//     (Info / Metadata / Versions / Audit / Workflows / AI Engine) — a
//     flexbox `min-width: auto` bug previously let wide tab content (e.g. a
//     long Metadata table) squeeze/shift the image pane.
//
// Both are exercised via the same `/folders?folder=<id>&id=<id>` deep-link
// entry point already covered in search_and_duplicates_fixes.e2e.spec.js.
// All backend responses are mocked via route interception so this test is
// deterministic and doesn't depend on live seed data.
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

// A moderately large fake EXIF payload — large enough that, pre-fix, it
// would visibly push the JSON block's Paper wider and (via the flexbox
// min-width bug) squeeze the sibling image pane.
const FAKE_EXIF = {
    Make: 'NIKON CORPORATION',
    Model: 'NIKON D850',
    LensModel: 'AF-S NIKKOR 24-70mm f/2.8E ED VR',
    FocalLength: '50 mm',
    ExposureTime: '1/250',
    FNumber: 8,
    ISO: 100,
    DateTimeOriginal: '2024:03:15 10:22:41',
    GPSLatitude: '37.7749 N',
    GPSLongitude: '122.4194 W',
    ColorSpace: 'sRGB',
    Software: 'Adobe Photoshop 25.0',
};

async function mockViewerAsset(page) {
    await page.route('**/api/v1/assets/exif-asset-1', async (route) => {
        route.fulfill({
            status: 200,
            contentType: 'application/json',
            body: JSON.stringify({
                id: 'exif-asset-1', uuid: 'exif-asset-1', title: 'Exif Layout Asset.png',
                status: 'ready',
                properties: {
                    content_type: 'image/png',
                    file_size: 512_000,
                    embedded_metadata: FAKE_EXIF,
                    metadata_field_count: Object.keys(FAKE_EXIF).length,
                },
                metadata: { content_type: 'image/png', file_size: 512_000 },
                content_type: 'image/png',
                size: 512_000,
                folder_id: 'folder-9',
                url: '/api/v1/assets/local/exif-asset-1',
                preview_url: '/api/v1/assets/local/exif-asset-1',
                editable: true,
            }),
        });
    });
    await page.route('**/api/v1/assets/local/exif-asset-1**', (route) => {
        route.fulfill({
            status: 200,
            contentType: 'image/png',
            // 1x1 transparent PNG
            body: Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=', 'base64'),
        });
    });
}

test.describe('AssetViewer — EXIF collapse & fixed image layout', () => {
    test.beforeEach(async ({ page }) => {
        await login(page);
        await mockEmptyFolderContents(page);
        await mockViewerAsset(page);
        await page.goto('/folders?folder=folder-9&id=exif-asset-1');
        await page.waitForLoadState('networkidle');
        await expect(page.getByRole('banner').getByText('Exif Layout Asset.png')).toBeVisible();
    });

    test('EXIF / IPTC / XMP Data section is collapsed by default and expands/collapses on click', async ({ page }) => {
        // Collapsed by default: the header is visible, but the raw JSON
        // content (e.g. the camera make) must not be in the DOM yet, since
        // the Collapse uses `unmountOnExit`.
        await expect(page.getByText('EXIF / IPTC / XMP Data')).toBeVisible();
        await expect(page.getByText(/NIKON CORPORATION/)).not.toBeVisible();
        await expect(page.getByText(/NIKON CORPORATION/)).toHaveCount(0);

        // Click the header to expand.
        await page.getByText('EXIF / IPTC / XMP Data').click();
        await expect(page.getByText(/NIKON CORPORATION/)).toBeVisible({ timeout: 5_000 });

        // Click again to collapse (the toggle icon has an aria-label that
        // flips between "Expand ..." / "Collapse ...").
        await page.getByLabel(/collapse exif/i).click();
        await expect(page.getByText(/NIKON CORPORATION/)).toHaveCount(0, { timeout: 5_000 });
    });

    test('left-hand image preview pane does not shift when switching inspector tabs', async ({ page }) => {
        const image = page.locator('img[src*="exif-asset-1"]').first();
        await expect(image).toBeVisible();

        const before = await image.boundingBox();
        expect(before).not.toBeNull();

        // Switch through several tabs, including ones likely to render wide
        // content (Metadata table, Audit log, AI Engine panel).
        for (const tabName of [/metadata/i, /versions/i, /audit/i, /workflows/i, /ai engine/i, /^info$/i]) {
            await page.getByRole('tab', { name: tabName }).click();
            // Give any async tab content a moment to render.
            await page.waitForTimeout(150);
            const after = await image.boundingBox();
            expect(after).not.toBeNull();
            expect(after.x).toBeCloseTo(before.x, 0);
            expect(after.y).toBeCloseTo(before.y, 0);
            expect(after.width).toBeCloseTo(before.width, 0);
            expect(after.height).toBeCloseTo(before.height, 0);
        }
    });
});
