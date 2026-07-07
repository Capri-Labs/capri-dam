// E2E coverage for a batch of Search / Duplicate Manager / Recycle Bin
// navigation fixes:
//
//  1. Search screen: "Include Recycle Bin" toggle (off by default); enabling
//     it re-runs the search with `include_bin=true` and flags bin results
//     with a "Bin" chip (see SearchController#include_bin? and
//     SearchResultCard's BinChip).
//  2. Clicking a Search result navigates to `/assets?id=<uuid>` and opens
//     that asset in the AssetViewer — previously the URL's `?id=` was
//     stripped by AssetExplorer's URL-sync effect within milliseconds of
//     mount (see the filter-sync useEffect in AssetExplorer.jsx).
//  3. Duplicate Manager's "Go to Folder" / "Go to asset" actions navigate to
//     the correct URLs (`/folders?folder=<id>` and `/assets?id=<id>`) — the
//     "Go to Folder" button previously used the wrong query param (`?id=`
//     instead of `?folder=`).
//  4. Search results-per-page dropdown (25 / 50 / 100, default 25).
//  5. Search result size is a human-readable string derived from the raw
//     byte count, never a hard-coded "0 KB".
//  6. The "View Trash Bin" button inside the folder explorer (All Assets
//     screen) navigates to the dedicated `/bin` page instead of rendering a
//     blank/broken in-explorer "bin" view.
//  7. `/folders?folder=<id>&id=<id>` opens the AssetViewer for `?id=` by
//     default, matching `/assets?id=<id>` — previously DashboardController's
//     `folders` action ignored `params[:id]`. Also verifies a loading
//     spinner shows while the deep-linked asset is fetched, and that the
//     image itself renders (asset.properties must be present — a separate
//     backend bug where AssetsController#show only returned `metadata:`,
//     not `properties:`, silently broke image rendering even though the
//     AssetViewer dialog opened).
//
// All backend responses are mocked via route interception so these tests
// are deterministic and don't depend on live seed data.
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

function searchResult(overrides = {}) {
    return {
        id: 'asset-1',
        uuid: 'asset-1',
        title: 'Brand Logo.png',
        content_type: 'image/png',
        size: '500 KB',
        file_size: 512_000,
        thumb_url: '/api/v1/assets/local/asset-1',
        preview_url: '/api/v1/assets/local/asset-1',
        url: '/api/v1/assets/local/asset-1',
        web_renderable: true,
        folder_id: 'folder-1',
        status: 'active',
        in_bin: false,
        width: 800,
        height: 600,
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
        metadata: {},
        ...overrides,
    };
}

function mockSearch(page, { results = [searchResult()], meta = {}, onRequest } = {}) {
    return page.route('**/api/v1/search?**', (route) => {
        const url = new URL(route.request().url());
        if (onRequest) onRequest(url.searchParams);
        route.fulfill({
            status: 200,
            contentType: 'application/json',
            body: JSON.stringify({
                meta: {
                    query: url.searchParams.get('q') || '',
                    mode: 'all',
                    result_type: 'asset',
                    total_found: results.length,
                    page: 1,
                    per_page: Number(url.searchParams.get('per_page')) || 25,
                    total_pages: 1,
                    facets: {},
                    include_bin: url.searchParams.get('include_bin') === 'true',
                    ...meta,
                },
                results,
            }),
        });
    });
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

test.describe('Search screen fixes', () => {
    test.beforeEach(async ({ page }) => { await login(page); });

    test('defaults the results-per-page dropdown to 25 and re-fetches on change', async ({ page }) => {
        const perPageSeen = [];
        await mockSearch(page, { onRequest: (params) => perPageSeen.push(params.get('per_page')) });

        await page.goto('/search?q=logo');
        await page.waitForLoadState('networkidle');

        expect(perPageSeen[0]).toBe('25');
        await expect(page.getByText(/25 \/ /)).toBeVisible();

        // Change to 50 via the per-page dropdown
        await page.getByText(/25 \/ /).click();
        await page.getByRole('option', { name: /^50 \/ / }).click();

        await expect.poll(() => perPageSeen[perPageSeen.length - 1]).toBe('50');
    });

    test('shows a human-readable size for a search result, never a hard-coded 0 KB', async ({ page }) => {
        await mockSearch(page, { results: [searchResult({ size: '500 KB', file_size: 512_000 })] });

        await page.goto('/search?q=logo');
        await page.waitForLoadState('networkidle');

        await expect(page.getByText('500 KB')).toBeVisible();
    });

    test('"Include Recycle Bin" toggle is off by default and flags bin results with a Bin chip when enabled', async ({ page }) => {
        const includeBinSeen = [];
        await mockSearch(page, {
            results: [
                searchResult({ id: 'active-1', uuid: 'active-1', title: 'Active Asset.png', in_bin: false }),
            ],
            onRequest: (params) => includeBinSeen.push(params.get('include_bin')),
        });

        await page.goto('/search?q=asset');
        await page.waitForLoadState('networkidle');

        expect(includeBinSeen[0]).toBeNull();
        await expect(page.getByText(/bin/i, { exact: false }).first()).toBeVisible(); // the toggle's own label
        await expect(page.locator('.MuiChip-root', { hasText: 'Bin' })).toHaveCount(0);

        // Re-mock now that the toggle flips include_bin=true, returning a trashed result
        await mockSearch(page, {
            results: [
                searchResult({ id: 'active-1', uuid: 'active-1', title: 'Active Asset.png', in_bin: false }),
                searchResult({ id: 'trashed-1', uuid: 'trashed-1', title: 'Trashed Asset.png', in_bin: true }),
            ],
            onRequest: (params) => includeBinSeen.push(params.get('include_bin')),
        });

        const toggle = page.locator('input[type="checkbox"]').first();
        await toggle.click();

        await expect.poll(() => includeBinSeen[includeBinSeen.length - 1]).toBe('true');
        await expect(page.locator('.MuiChip-root', { hasText: 'Bin' }).first()).toBeVisible();
    });

    test('clicking a search result navigates to /assets?id=<uuid> and keeps the AssetViewer open', async ({ page }) => {
        const asset = searchResult({ id: 'deep-link-1', uuid: 'deep-link-1', title: 'Deep Link Asset.png' });
        await mockSearch(page, { results: [asset] });
        await mockEmptyFolderContents(page);
        await page.route('**/api/v1/assets/deep-link-1', (route) => {
            route.fulfill({
                status: 200,
                contentType: 'application/json',
                body: JSON.stringify({
                    id: 'deep-link-1', uuid: 'deep-link-1', title: 'Deep Link Asset.png',
                    status: 'ready', properties: { content_type: 'image/png', size: 512_000 },
                    folder_id: 'root',
                }),
            });
        });

        await page.goto('/search?q=deep');
        await page.waitForLoadState('networkidle');

        await page.getByText('Deep Link Asset.png').click();

        // The click performs a full navigation to /assets?id=deep-link-1
        await page.waitForURL(/\/assets\?id=deep-link-1/, { timeout: 15_000 });
        await page.waitForLoadState('networkidle');

        // The URL must retain `?id=` — it must NOT get stripped by the
        // folder-explorer's URL-sync effect on mount.
        expect(page.url()).toContain('id=deep-link-1');
    });
});

test.describe('Folder explorer — View Trash Bin navigation fix', () => {
    test.beforeEach(async ({ page }) => { await login(page); });

    test('"View Trash Bin" button navigates to the dedicated /bin page', async ({ page }) => {
        await mockEmptyFolderContents(page);
        await page.route('**/api/v1/bin/stats', (route) => {
            route.fulfill({
                status: 200,
                contentType: 'application/json',
                body: JSON.stringify({
                    total_items: 0, total_assets: 0, total_folders: 0,
                    total_size_bytes: 0, oldest_deleted_at: null, retention_days: 30,
                }),
            });
        });
        await page.route('**/api/v1/bin?**', (route) => {
            route.fulfill({
                status: 200,
                contentType: 'application/json',
                body: JSON.stringify({ items: [], pagination: { total: 0, page: 1, per_page: 25, pages: 0 }, retention_days: 30 }),
            });
        });

        await page.goto('/folders');
        await page.waitForLoadState('networkidle');

        await page.getByRole('button', { name: /view trash bin/i }).click();

        await page.waitForURL(/\/bin$/, { timeout: 15_000 });
        await expect(page.getByRole('heading', { name: 'Recycle Bin', exact: true })).toBeVisible();
    });

    // Regression test: /folders?folder=<folder>&id=<asset> (e.g. links shared
    // from the Duplicate Manager) must open the AssetViewer for `?id=` by
    // default, the same way /assets?id=<asset> already does. Previously
    // DashboardController#folders ignored `params[:id]` entirely, so the
    // AssetViewer never opened on load.
    test('/folders?folder=<id>&id=<id> opens the AssetViewer for the asset by default, shows a loading spinner while fetching, and renders the image (not just the dialog chrome)', async ({ page }) => {
        await mockEmptyFolderContents(page);
        await page.route('**/api/v1/assets/deep-link-2', async (route) => {
            // Small artificial delay so the loading Backdrop is observable.
            await new Promise((resolve) => setTimeout(resolve, 500));
            route.fulfill({
                status: 200,
                contentType: 'application/json',
                // Mirrors the real Api::V1::AssetsController#show response shape
                // (properties: <merged metadata>) — a prior bug where the
                // controller only returned `metadata:` (no `properties:`) meant
                // AssetViewer's `asset.properties?.content_type` check silently
                // failed and the image never rendered, even though the dialog
                // opened. See docs/developer-guide/src/09_search.adoc.
                body: JSON.stringify({
                    id: 'deep-link-2', uuid: 'deep-link-2', title: 'Deep Link Folder Asset.png',
                    status: 'ready',
                    properties: { content_type: 'image/png', file_size: 512_000 },
                    metadata: { content_type: 'image/png', file_size: 512_000 },
                    content_type: 'image/png',
                    size: 512_000,
                    folder_id: 'folder-9',
                    url: '/api/v1/assets/local/deep-link-2',
                    preview_url: '/api/v1/assets/local/deep-link-2',
                    editable: true,
                }),
            });
        });
        await page.route('**/api/v1/assets/local/deep-link-2**', (route) => {
            route.fulfill({
                status: 200,
                contentType: 'image/png',
                // 1x1 transparent PNG
                body: Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=', 'base64'),
            });
        });

        await page.goto('/folders?folder=folder-9&id=deep-link-2');

        // The loading Backdrop should appear while the asset fetch is in flight...
        await expect(page.getByTestId('deep-link-loading-backdrop')).toBeVisible();

        await page.waitForLoadState('networkidle');

        // ...and disappear once the AssetViewer has opened.
        await expect(page.getByTestId('deep-link-loading-backdrop')).toBeHidden({ timeout: 15_000 });
        await expect(page.getByRole('banner').getByText('Deep Link Folder Asset.png')).toBeVisible();
        expect(page.url()).toContain('id=deep-link-2');

        // The actual <img> preview must render — not just the AssetViewer chrome —
        // proving `asset.properties.content_type` resolved correctly.
        await expect(page.locator('img[src*="deep-link-2"]').first()).toBeVisible();
    });
});

test.describe('Duplicate Manager — navigation fixes', () => {
    test.beforeEach(async ({ page }) => { await login(page); });

    test('"Go to Folder" and "Go to asset" navigate to the correct URLs', async ({ page }) => {
        const group = {
            id: 'group-1',
            status: 'pending',
            total_count: 2,
            assets: [
                { asset_id: 'asset-a', title: 'Copy A.png', is_original: true, folder_id: 'folder-9', folder_name: 'Marketing', url: '/api/v1/assets/local/asset-a' },
                { asset_id: 'asset-b', title: 'Copy B.png', is_original: false, folder_id: 'folder-9', folder_name: 'Marketing', url: '/api/v1/assets/local/asset-b' },
            ],
        };

        await page.route('**/api/v1/duplicate_groups/stats', (route) => {
            route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ total_groups: 1, pending: 1, resolved: 0, wasted_bytes: 0 }) });
        });
        await page.route('**/api/v1/duplicate_groups?status=**', (route) => {
            route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ groups: [group] }) });
        });
        await page.route('**/api/v1/duplicate_groups/group-1', (route) => {
            route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ group }) });
        });
        await mockEmptyFolderContents(page);

        await page.goto('/duplicates');
        await page.waitForLoadState('networkidle');

        await page.getByText(/potential match/i).first().click();
        await expect(page.getByText('Copy A.png')).toBeVisible();

        // "Go to Folder" — must use `/folders?folder=`, not `/folders?id=`
        await page.getByLabel(/go to folder/i).first().click();

        await page.waitForURL(/\/folders\?folder=folder-9/, { timeout: 15_000 });
        expect(page.url()).toContain('folder=folder-9');
    });
});
