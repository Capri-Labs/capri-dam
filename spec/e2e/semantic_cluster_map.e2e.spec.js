// Real end-to-end E2E test for the Semantic Cluster Map
// (app/javascript/components/Collections/SemanticClusterMap.jsx), opened via
// the "View AI Map" button on a Collection's detail workspace.
//
// Prior E2E coverage (spec/e2e/collections_workspace.e2e.spec.js) drives
// smart-rule configuration and manual asset management, but never opens the
// cluster map dialog itself — closing the "semantic cluster map interactions"
// pending gap for the Search & Discovery module (the map is reached from
// Collections, but is the same semantic-embedding-visualization feature
// described in docs/product-info/src/03_search_and_discovery.adoc).
//
// This test creates a real collection, attaches real assets to it via the
// real `POST /api/v1/collections/:slug/assets` endpoint, opens the map via
// the real `GET /api/v1/collections/:slug/cluster_map` endpoint, and verifies
// nodes render for each attached asset plus the hover-tooltip interaction —
// without mocking any collection/asset API responses.
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

test.describe('Semantic Cluster Map — real E2E', () => {
    test.beforeEach(async ({ page }) => {
        await login(page);
    });

    test('View AI Map renders a node per real collection asset and supports hover interaction', async ({ page }) => {
        test.setTimeout(60_000);

        await page.goto('/dashboard');
        await page.waitForLoadState('networkidle');
        const csrfToken = await page.evaluate(() => document.querySelector('meta[name="csrf-token"]')?.content);
        const stamp = Date.now();

        const buffer = Buffer.from(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
            'base64',
        );

        const createAsset = async (title) => {
            const res = await page.request.post('/api/v1/assets', {
                multipart: { file: { name: `${title.replace(/\s+/g, '-')}.png`, mimeType: 'image/png', buffer }, title },
                headers: { 'X-CSRF-Token': csrfToken },
            });
            expect(res.ok()).toBe(true);
            return res.json();
        };

        const titleA = `Cluster Map Asset A ${stamp}`;
        const titleB = `Cluster Map Asset B ${stamp}`;
        // POST /api/v1/assets only returns { id, status } (not title/etc.), so
        // the expected titles are tracked separately rather than read back.
        const assetA = await createAsset(titleA);
        const assetB = await createAsset(titleB);

        const collectionRes = await page.request.post('/api/v1/collections', {
            data: { collection: { name: `Cluster Map E2E ${stamp}` } },
            headers: { 'X-CSRF-Token': csrfToken, 'Content-Type': 'application/json' },
        });
        expect(collectionRes.ok()).toBe(true);
        const collection = await collectionRes.json();

        try {
            for (const asset of [ assetA, assetB ]) {
                const addRes = await page.request.post(`/api/v1/collections/${collection.slug}/assets`, {
                    data: { asset_id: asset.id },
                    headers: { 'X-CSRF-Token': csrfToken, 'Content-Type': 'application/json' },
                });
                expect(addRes.ok()).toBe(true);
            }

            const clusterMapResponse = page.waitForResponse((res) =>
                res.url().includes(`/api/v1/collections/${collection.slug}/cluster_map`) && res.ok());

            await page.goto(`/collections/${collection.slug}`);
            await page.waitForLoadState('networkidle');

            await page.getByRole('button', { name: /view ai map/i }).click();
            const mapRes = await clusterMapResponse;
            const mapPayload = await mapRes.json();

            // Real endpoint, real assets: one node per attached asset.
            expect(mapPayload.nodes).toHaveLength(2);
            const nodeTitles = mapPayload.nodes.map((n) => n.title);
            expect(nodeTitles).toEqual(expect.arrayContaining([ titleA, titleB ]));

            await expect(page.getByText('Semantic Cluster Map')).toBeVisible();

            // Hovering a node reveals the tooltip overlay with that asset's title.
            const firstNode = page.getByTestId('cluster-map-node').first();
            await expect(firstNode).toBeVisible({ timeout: 10_000 });
            await firstNode.hover();
            await expect(page.getByLabel('Semantic Cluster Map').getByText(nodeTitles[0])).toBeVisible();

            // Closing the dialog works.
            await page.getByTestId('CloseIcon').click();
            await expect(page.getByText('Semantic Cluster Map')).not.toBeVisible();
        } finally {
            await page.request.delete(`/api/v1/collections/${collection.slug}`, { headers: { 'X-CSRF-Token': csrfToken } }).catch(() => {});
            for (const asset of [ assetA, assetB ]) {
                await page.request.delete(`/api/v1/assets/${asset.id}`, { headers: { 'X-CSRF-Token': csrfToken } }).catch(() => {});
            }
            await page.request.delete('/api/v1/bin/bulk_destroy', {
                headers: { 'X-CSRF-Token': csrfToken, 'Content-Type': 'application/json' },
                data: { items: [ { id: assetA.id, type: 'asset' }, { id: assetB.id, type: 'asset' } ] },
            }).catch(() => {});
        }
    });
});
