// Additional E2E coverage for `app/javascript/components/Folders/**` flows
// that previously had no e2e regression tests (Jest-only or completely
// uncovered): the ProductID filename → metadata attachment on upload, and
// several AssetViewer/AssetExplorer dialogs (Apply Metadata Schema, AI
// Analysis, Pin to Collection, Asset Stats, Audit tab, Versions restore,
// Trigger Workflow). All backend responses are mocked via route interception
// so these tests are deterministic and don't depend on live seed data.
//
// Runs against a live Rails server (set E2E_BASE_URL, E2E_EMAIL, E2E_PASSWORD).

const { test, expect } = require('./fixtures');

const SAMPLE_PNG_BUFFER = Buffer.from(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    'base64'
);

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
        if (route.request().method() !== 'GET') return route.continue();
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

function mockUploadWorkspaceBootstrap(page) {
    return Promise.all([
        page.route('**/api/v1/metadata_schemas', (route) => {
            if (route.request().method() !== 'GET') return route.continue();
            route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify([]) });
        }),
        page.route('**/api/v1/upload_restrictions', (route) => {
            route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ allowed_mime_types: [] }) });
        }),
    ]);
}

// Mocks a folder listing with exactly one asset (so grid-level selection /
// per-card actions have something to act on) plus that asset's detail,
// preview bytes, and asset-scoped metadata_schema endpoint.
async function mockFolderWithOneAsset(page, { folderId, assetId, title }) {
    await page.route(`**/api/v1/folders/${folderId}*`, (route) => {
        if (route.request().method() !== 'GET') return route.continue();
        route.fulfill({
            status: 200,
            contentType: 'application/json',
            body: JSON.stringify({
                folders: [],
                assets: [ {
                    id: assetId, uuid: assetId, title, status: 'ready',
                    content_type: 'image/png', size: 2048,
                    url: `/api/v1/assets/local/${assetId}`,
                    preview_url: `/api/v1/assets/local/${assetId}`,
                    properties: { content_type: 'image/png', file_size: 2048 },
                } ],
                breadcrumbs: [ { id: 'root', name: 'Home' }, { id: folderId, name: 'Coverage Folder' } ],
                sort: { field: 'created_at', direction: 'desc' },
            }),
        });
    });
    await page.route(`**/api/v1/assets/${assetId}`, (route) => {
        if (route.request().method() !== 'GET') return route.continue();
        route.fulfill({
            status: 200,
            contentType: 'application/json',
            body: JSON.stringify({
                id: assetId, uuid: assetId, title, status: 'ready',
                properties: { content_type: 'image/png', file_size: 2048 },
                metadata: { content_type: 'image/png', file_size: 2048 },
                content_type: 'image/png', size: 2048, folder_id: folderId,
                url: `/api/v1/assets/local/${assetId}`,
                preview_url: `/api/v1/assets/local/${assetId}`,
                editable: true,
            }),
        });
    });
    await page.route(`**/api/v1/assets/local/${assetId}**`, (route) => {
        route.fulfill({ status: 200, contentType: 'image/png', body: SAMPLE_PNG_BUFFER });
    });
    await page.route(`**/api/v1/assets/${assetId}/metadata_schema`, (route) => {
        route.fulfill({ status: 404, contentType: 'application/json', body: JSON.stringify({ error: 'not found' }) });
    });
}

test.describe('Folders — Upload attaches ProductID-derived metadata', () => {
    test.beforeEach(async ({ page }) => { await login(page); });

    test('a filename matching ProductID-LanguageCode-AssetTypeCode.ext attaches dam:product_id/language_code/asset_type on upload', async ({ page }) => {
        await mockEmptyFolderContents(page);
        await mockUploadWorkspaceBootstrap(page);
        await page.goto('/folders');
        await page.waitForLoadState('networkidle');
        await page.getByRole('button', { name: /upload asset/i }).click();
        await expect(page.getByText('Upload & Enrich')).toBeVisible();

        await page.route('**/api/v1/assets/check_hashes', (route) => {
            route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ duplicates: {} }) });
        });

        const fileInput = page.locator('input[type="file"]');
        await fileInput.setInputFiles({
            name: '012993112028-en-FR01.png',
            mimeType: 'image/png',
            buffer: SAMPLE_PNG_BUFFER,
        });
        await expect(page.locator('input[value="012993112028-en-FR01.png"]').first()).toBeVisible({ timeout: 15_000 });

        let uploadedMetadata = null;
        await page.route('**/api/v1/assets', async (route) => {
            if (route.request().method() !== 'POST') return route.continue();
            const body = route.request().postData() || '';
            const match = body.match(/name="metadata"\r?\n\r?\n([^\r\n]+)/);
            if (match) {
                try { uploadedMetadata = JSON.parse(match[1]); } catch (_) { /* ignore */ }
            }
            route.fulfill({
                status: 201,
                contentType: 'application/json',
                body: JSON.stringify({ id: 'product-asset-1', uuid: 'product-asset-1', title: '012993112028-en-FR01.png' }),
            });
        });

        await page.getByRole('button', { name: /upload \(1\)/i }).click();
        await expect.poll(() => uploadedMetadata).not.toBeNull();

        expect(uploadedMetadata['dam:product_id']).toBe('012993112028');
        expect(uploadedMetadata['dam:language_code']).toBe('en');
        expect(uploadedMetadata['dam:asset_type']).toBe('FR01');
    });
});

test.describe('Folders — Apply Metadata Schema to selected assets', () => {
    test.beforeEach(async ({ page }) => { await login(page); });

    test('selecting an asset and applying a schema PATCHes /api/v1/assets/:id/metadata with the chosen schema_id', async ({ page }) => {
        const folderId = 'folder-schema-1';
        const assetId  = 'schema-asset-1';
        await mockFolderWithOneAsset(page, { folderId, assetId, title: 'Schema Target.png' });

        await page.route('**/api/v1/metadata_schemas', (route) => {
            if (route.request().method() !== 'GET') return route.continue();
            route.fulfill({
                status: 200,
                contentType: 'application/json',
                body: JSON.stringify([
                    { id: 42, name: 'Coverage Schema', level: 'root', is_builtin: false, tabs: [], children: [] },
                ]),
            });
        });

        await page.goto(`/folders?folder=${folderId}`);
        await page.waitForLoadState('networkidle');
        await expect(page.getByText('Schema Target.png')).toBeVisible();

        // Select the asset via its grid checkbox so the Tools menu appears.
        await page.getByRole('checkbox').first().click();
        await page.getByRole('button', { name: /tools/i }).click();
        await page.getByText(/apply schema to assets/i).click();

        await expect(page.getByRole('heading', { name: 'Apply Metadata Schema' })).toBeVisible();
        await page.getByText('Coverage Schema', { exact: true }).click();

        let patchedBody = null;
        await page.route(`**/api/v1/assets/${assetId}/metadata`, (route) => {
            if (route.request().method() !== 'PATCH') return route.continue();
            patchedBody = route.request().postDataJSON();
            route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ id: assetId }) });
        });

        await page.getByRole('button', { name: /apply "coverage schema"/i }).click();
        await expect.poll(() => patchedBody).not.toBeNull();
        expect(patchedBody.schema_id).toBe(42);
    });
});

test.describe('Folders — AI Analysis dialog applies suggested tags', () => {
    test.beforeEach(async ({ page }) => { await login(page); });

    test('running AI Analysis from the grid and applying suggested tags PATCHes the asset with the selected tags', async ({ page }) => {
        const folderId = 'folder-ai-1';
        const assetId  = 'ai-asset-1';
        await mockFolderWithOneAsset(page, { folderId, assetId, title: 'AI Target.png' });

        await page.route(`**/api/v1/assets/${assetId}/ai_analysis`, (route) => {
            if (route.request().method() !== 'POST') return route.continue();
            route.fulfill({
                status: 200,
                contentType: 'application/json',
                body: JSON.stringify({
                    status: 'completed',
                    labels: [ 'product', 'studio' ],
                    colors: [],
                    quality_score: 88,
                    suggested_tags: [ 'hero', 'approved' ],
                    description: 'A studio product photo.',
                    similar_assets: [],
                }),
            });
        });

        await page.goto(`/folders?folder=${folderId}`);
        await page.waitForLoadState('networkidle');
        await expect(page.getByText('AI Target.png')).toBeVisible();

        await page.getByTestId('asset-ai-analysis-toggle').click();
        await expect(page.getByText('A studio product photo.').first()).toBeVisible();
        await expect(page.getByText('hero', { exact: true })).toBeVisible();

        let patchedBody = null;
        await page.route(`**/api/v1/assets/${assetId}`, (route) => {
            if (route.request().method() !== 'PATCH') return route.continue();
            patchedBody = route.request().postDataJSON();
            route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ id: assetId }) });
        });

        await page.getByRole('button', { name: /apply suggested tags/i }).click();
        await expect.poll(() => patchedBody).not.toBeNull();
        expect(patchedBody.asset.tags).toEqual(expect.arrayContaining([ 'hero', 'approved' ]));
    });
});

test.describe('Folders — AssetViewer toolbar & tabs (Pin, Stats, Audit, Versions)', () => {
    test.beforeEach(async ({ page }) => {
        await login(page);
        await mockEmptyFolderContents(page);
    });

    async function openViewer(page, assetId, title) {
        await page.route(`**/api/v1/assets/${assetId}`, (route) => {
            if (route.request().method() !== 'GET') return route.continue();
            route.fulfill({
                status: 200,
                contentType: 'application/json',
                body: JSON.stringify({
                    id: assetId, uuid: assetId, title, status: 'ready',
                    properties: { content_type: 'image/png', file_size: 2048 },
                    metadata: { content_type: 'image/png', file_size: 2048 },
                    content_type: 'image/png', size: 2048, folder_id: 'folder-9',
                    url: `/api/v1/assets/local/${assetId}`,
                    preview_url: `/api/v1/assets/local/${assetId}`,
                    editable: true,
                }),
            });
        });
        await page.route(`**/api/v1/assets/local/${assetId}**`, (route) => {
            route.fulfill({ status: 200, contentType: 'image/png', body: SAMPLE_PNG_BUFFER });
        });
        await page.goto(`/folders?folder=folder-9&id=${assetId}`);
        await page.waitForLoadState('networkidle');
        await expect(page.getByRole('banner').getByText(title)).toBeVisible();
    }

    test('Pin to Collection dialog lists collections and pins the asset to one', async ({ page }) => {
        const assetId = 'pin-asset-1';
        await openViewer(page, assetId, 'Pin Target.png');

        await page.route(/\/api\/v1\/collections(\?|$)/, (route) => {
            if (route.request().method() !== 'GET') return route.continue();
            route.fulfill({
                status: 200,
                contentType: 'application/json',
                body: JSON.stringify([
                    { id: 1, slug: 'summer-campaign', name: 'Summer Campaign', collection_type: 'manual', pinned_for_asset: false, assets_count: 3 },
                ]),
            });
        });

        await page.getByTestId('asset-pin-to-collection-toggle').click();
        await expect(page.getByText('Pin to Collections')).toBeVisible();
        await expect(page.getByText('Summer Campaign')).toBeVisible();

        let pinnedBody = null;
        await page.route('**/api/v1/collections/summer-campaign/assets', (route) => {
            if (route.request().method() !== 'POST') return route.continue();
            pinnedBody = route.request().postDataJSON();
            route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ ok: true }) });
        });

        await page.getByText('Summer Campaign').click();
        await expect.poll(() => pinnedBody).not.toBeNull();
        expect(pinnedBody.asset_id).toBe(assetId);
    });

    test('Asset Stats popover shows real view/download/share counts from the stats endpoint', async ({ page }) => {
        const assetId = 'stats-asset-1';
        await openViewer(page, assetId, 'Stats Target.png');

        await page.route(`**/api/v1/assets/${assetId}/stats`, (route) => {
            route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ views: 12, downloads: 4, shares: 1 }) });
        });

        await page.getByTestId('asset-stats-toggle').click();
        await expect(page.getByRole('heading', { name: '12', exact: true })).toBeVisible();
        await expect(page.getByRole('heading', { name: '4', exact: true })).toBeVisible();
        await expect(page.getByRole('heading', { name: '1', exact: true })).toBeVisible();
    });

    test('Audit tab renders the asset audit trail history', async ({ page }) => {
        const assetId = 'audit-asset-1';
        await openViewer(page, assetId, 'Audit Target.png');

        await page.route(`**/api/v1/assets/${assetId}/audit_trail`, (route) => {
            route.fulfill({
                status: 200,
                contentType: 'application/json',
                body: JSON.stringify({
                    audit_trail: [
                        { id: 2, version_number: 2, action_type: 'metadata_updated', created_by_id: 'Admin User', created_at: '2026-01-02T00:00:00Z', properties: {} },
                        { id: 1, version_number: 1, action_type: 'asset_ingested', created_by_id: 'Admin User', created_at: '2026-01-01T00:00:00Z', properties: {} },
                    ],
                }),
            });
        });

        await page.getByRole('tab', { name: /audit/i }).click();
        await expect(page.getByText(/admin user/i).first()).toBeVisible({ timeout: 10_000 });
    });

    test('Versions tab lists versions and restoring one calls the restore endpoint', async ({ page }) => {
        const assetId = 'versions-asset-1';
        await openViewer(page, assetId, 'Versions Target.png');

        await page.route(`**/api/v1/assets/${assetId}/versions`, (route) => {
            route.fulfill({
                status: 200,
                contentType: 'application/json',
                body: JSON.stringify({
                    versions: [
                        { id: 'v1', version_number: 2, is_active: true, action_type: 'Image Edited', created_at: '2026-01-02T00:00:00Z', created_by: 'Admin User', size: '2 KB' },
                        { id: 'v2', version_number: 1, is_active: false, action_type: 'Asset Ingested', created_at: '2026-01-01T00:00:00Z', created_by: 'Admin User', size: '1 KB' },
                    ],
                }),
            });
        });

        await page.getByRole('tab', { name: /versions/i }).click();
        await expect(page.getByText(/admin user/i).first()).toBeVisible({ timeout: 10_000 });

        let restoreCalled = false;
        await page.route(`**/api/v1/assets/${assetId}/versions/v2/restore`, (route) => {
            restoreCalled = true;
            route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ id: assetId }) });
        });

        await page.getByRole('button', { name: /restore/i }).first().click();
        await expect.poll(() => restoreCalled).toBe(true);
    });
});

test.describe('Folders — Trigger Workflow dialog', () => {
    test.beforeEach(async ({ page }) => { await login(page); });

    test('selecting an asset and triggering an active workflow calls the bulk_trigger endpoint', async ({ page }) => {
        const folderId = 'folder-workflow-1';
        const assetId  = 'workflow-asset-1';
        await mockFolderWithOneAsset(page, { folderId, assetId, title: 'Workflow Target.png' });

        await page.route('**/workflows.json', (route) => {
            route.fulfill({
                status: 200,
                contentType: 'application/json',
                body: JSON.stringify([
                    { id: 7, name: 'Coverage Workflow', status: 'active' },
                    { id: 8, name: 'Draft Workflow', status: 'draft' },
                ]),
            });
        });

        await page.goto(`/folders?folder=${folderId}`);
        await page.waitForLoadState('networkidle');
        await expect(page.getByText('Workflow Target.png')).toBeVisible();

        await page.getByRole('checkbox').first().click();
        await page.getByRole('button', { name: /^workflow$/i }).click();
        await expect(page.getByText('Coverage Workflow')).toBeVisible();
        // The inactive/draft workflow must not be offered.
        await expect(page.getByText('Draft Workflow')).toHaveCount(0);

        await page.getByText('Coverage Workflow', { exact: true }).click();

        let triggeredBody = null;
        await page.route('**/api/v1/workflows/bulk_trigger', (route) => {
            triggeredBody = route.request().postDataJSON();
            route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ triggered: 1 }) });
        });

        await page.getByRole('button', { name: /^trigger$/i }).click();
        await expect.poll(() => triggeredBody).not.toBeNull();
        expect(triggeredBody.workflow_id).toBe(7);
    });
});
