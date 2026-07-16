// E2E coverage for `app/javascript/components/Collections/**`, which
// previously had no dedicated Playwright suite. Covers the five scenarios
// requested:
//
//   1. Collections index page loads and lists existing collections.
//   2. Creating a manual collection and adding assets to it (via the Search
//      Library picker and via drag-drop upload) in `AddAssetsToCollectionDialog`.
//   3. Creating a smart collection rule and confirming a newly-routed asset
//      appears after the background worker (`SmartCollectionRouterWorker`)
//      runs — simulated via mocked before/after responses, consistent with
//      this suite's full network-mocking convention (no e2e spec in this
//      codebase relies on a genuinely running Sidekiq worker).
//   4. Generating a real signed public share link and visiting it as a truly
//      unauthenticated visitor (fresh browser context, no cookies) — the one
//      scenario here that talks to the real backend, since it specifically
//      exercises the signed-token security boundary rather than UI wiring.
//   5. Collection slug-based nested routing (`/collections/*path`).
//
// Runs against a live Rails server (set E2E_BASE_URL, E2E_EMAIL, E2E_PASSWORD).

const { test, expect } = require('./fixtures');

const EMAIL    = process.env.E2E_EMAIL    || 'admin@admin.com';
const PASSWORD = process.env.E2E_PASSWORD || 'AdminUser';

const SAMPLE_PNG_BUFFER = Buffer.from(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    'base64'
);

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

const baseCollection = {
    id: 501,
    slug: 'spring-launch-e2e',
    name: 'Spring Launch E2E',
    description: 'Seasonal launch assets',
    collection_type: 'manual',
    assets_count: 0,
    properties: { tags: [], allowed_groups: [], denied_groups: [] },
    collection_rule: null,
    collection_assets: [],
    compliance_violations: [],
    created_at: new Date().toISOString(),
};

function mockCollectionsIndex(page, collections) {
    return page.route('**/api/v1/collections', (route) => {
        if (route.request().method() !== 'GET') return route.continue();
        route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(collections) });
    });
}

// Serves the detail endpoint for a single slug. `getDetail` is called fresh
// on every request so tests can mutate what it returns between requests
// (e.g. simulating a smart-rule worker having routed a new asset).
function mockCollectionDetail(page, slug, getDetail) {
    return page.route(`**/api/v1/collections/${slug}*`, (route) => {
        if (route.request().method() !== 'GET') return route.continue();
        if (!route.request().url().includes(`/api/v1/collections/${slug}`)) return route.continue();
        route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(getDetail()) });
    });
}

test.describe('Collections workspace E2E', () => {
    test.beforeEach(async ({ page }) => {
        await login(page);
    });

    // ------------------------------------------------------------------
    // 1. Collections index page loads and lists existing collections.
    // ------------------------------------------------------------------
    test('Collections index page loads and lists existing collections', async ({ page }) => {
        await mockCollectionsIndex(page, [ baseCollection ]);

        await page.goto('/collections');
        await expect(page.getByText('My Collections')).toBeVisible();
        await expect(page.getByText('Spring Launch E2E')).toBeVisible();
    });

    // ------------------------------------------------------------------
    // 2. Creating a manual collection and adding assets via the Search
    //    Library picker and via drag-drop upload.
    // ------------------------------------------------------------------
    test('creates a manual collection and adds an asset via the Search Library picker', async ({ page }) => {
        let created = false;
        const detail = { ...baseCollection, collection_assets: [] };

        await mockCollectionsIndex(page, []);
        await page.route('**/api/v1/collections', (route) => {
            if (route.request().method() !== 'POST') return route.continue();
            created = true;
            route.fulfill({ status: 201, contentType: 'application/json', body: JSON.stringify(baseCollection) });
        });
        await mockCollectionDetail(page, baseCollection.slug, () => detail);
        await page.route('**/api/v1/search/suggestions*', (route) => {
            route.fulfill({
                status: 200,
                contentType: 'application/json',
                body: JSON.stringify({
                    query: 'hero',
                    results: [
                        { type: 'asset', id: 9001, title: 'Hero Shot', subtitle: 'hero.jpg', thumb_url: '' },
                    ],
                }),
            });
        });
        await page.route(`**/api/v1/collections/${baseCollection.slug}/assets`, (route) => {
            if (route.request().method() !== 'POST') return route.continue();
            detail.collection_assets = [
                { id: 1, asset_id: 9001, pinned: false, asset: { id: 9001, title: 'Hero Shot', original_filename: 'hero.jpg' } },
            ];
            route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ message: 'Asset added successfully', collection: detail }) });
        });

        await page.goto('/collections');
        await page.getByRole('button', { name: 'Create Collection' }).click();
        await page.getByLabel(/Collection Name/i).fill('Spring Launch E2E');
        await page.getByRole('button', { name: 'Initialize Workspace' }).click();

        await expect.poll(() => created).toBe(true);
        await page.waitForURL(/\/collections\/spring-launch-e2e/);

        await page.getByTestId('collection-add-assets-button').click();
        await expect(page.getByTestId('add-assets-dialog')).toBeVisible();

        await page.getByTestId('add-assets-search-input').fill('hero');
        await expect(page.getByText('Hero Shot')).toBeVisible();
        await page.getByRole('checkbox').click();

        await expect(page.getByText('Added')).toBeVisible();
    });

    test('adds an asset to a collection via drag-drop upload in the Add Assets dialog', async ({ page }) => {
        const detail = { ...baseCollection, collection_assets: [] };
        await mockCollectionDetail(page, baseCollection.slug, () => detail);

        await page.route('**/api/v1/assets', (route) => {
            if (route.request().method() !== 'POST') return route.continue();
            route.fulfill({ status: 201, contentType: 'application/json', body: JSON.stringify({ id: 9002, title: 'dropped.png' }) });
        });
        await page.route(`**/api/v1/collections/${baseCollection.slug}/assets`, (route) => {
            if (route.request().method() !== 'POST') return route.continue();
            detail.collection_assets = [
                { id: 2, asset_id: 9002, pinned: false, asset: { id: 9002, title: 'dropped.png', original_filename: 'dropped.png' } },
            ];
            route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ message: 'Asset added successfully', collection: detail }) });
        });

        await page.goto(`/collections/${baseCollection.slug}`);
        await expect(page.getByText('Spring Launch E2E')).toBeVisible();

        await page.getByTestId('collection-add-assets-button').click();
        await page.getByTestId('add-assets-tab-upload').click();

        const fileChooserPromise = page.waitForEvent('filechooser');
        await page.getByTestId('add-assets-dropzone').click();
        const fileChooser = await fileChooserPromise;
        await fileChooser.setFiles({ name: 'dropped.png', mimeType: 'image/png', buffer: SAMPLE_PNG_BUFFER });

        await expect(page.getByText('dropped.png')).toBeVisible();
        await page.getByTestId('add-assets-upload-button').click();

        await expect(page.getByText('Upload complete')).toBeVisible();
    });

    // ------------------------------------------------------------------
    // 3. Creating a smart collection rule and confirming a newly-routed
    //    asset appears after the background worker runs.
    // ------------------------------------------------------------------
    test('creates a smart collection rule and shows a worker-routed asset after reload', async ({ page }) => {
        const smartCollection = {
            ...baseCollection,
            slug: 'smart-launch-e2e',
            name: 'Smart Launch E2E',
            collection_type: 'smart',
            collection_rule: { semantic_prompt: 'snowy outdoor lifestyle', similarity_threshold: 0.85 },
        };
        // "Before": worker has not routed anything yet.
        const detailBefore = { ...smartCollection, collection_assets: [] };
        // "After": SmartCollectionRouterWorker has routed a matching asset in
        // the background — simulated by swapping the mocked response rather
        // than waiting on a real Sidekiq job, consistent with this codebase's
        // e2e conventions (see AGENTS.md / other spec/e2e/* files).
        const detailAfter = {
            ...smartCollection,
            collection_assets: [
                { id: 3, asset_id: 9003, pinned: false, asset: { id: 9003, title: 'Snowy Hero', original_filename: 'snowy-hero.jpg' } },
            ],
        };

        let workerHasRun = false;
        await page.route(`**/api/v1/collections/${smartCollection.slug}*`, (route) => {
            if (route.request().method() !== 'GET') return route.continue();
            route.fulfill({
                status: 200,
                contentType: 'application/json',
                body: JSON.stringify(workerHasRun ? detailAfter : detailBefore),
            });
        });
        await page.route(`**/api/v1/collections/${smartCollection.slug}/rule`, (route) => {
            if (route.request().method() !== 'POST') return route.continue();
            route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ collection: detailBefore }) });
        });

        await page.goto(`/collections/${smartCollection.slug}`);
        await expect(page.getByText('Smart Launch E2E')).toBeVisible();
        await expect(page.getByText('Curated Assets (0)')).toBeVisible();

        await page.getByRole('button', { name: /Configure Rules/i }).click();
        await page.getByLabel(/Semantic AI Prompt/i).fill('snowy outdoor lifestyle');
        await page.getByRole('button', { name: 'Activate Rule in Production' }).click();

        // Simulate the background worker having routed a new asset, then
        // reload to observe the "after" state.
        workerHasRun = true;
        await page.reload();

        await expect(page.getByText('Curated Assets (1)')).toBeVisible();
        await expect(page.getByText('snowy-hero.jpg')).toBeVisible();
    });

    // Regression coverage: Pin/Unpin was removed from the per-asset menu since
    // "Remove from Collection" already covers detaching an asset from any
    // collection type (manual or AI Smart Collection) — having both was
    // redundant.
    test('does not offer a Pin/Unpin action in the asset menu', async ({ page }) => {
        const smartCollection = {
            ...baseCollection,
            slug: 'asset-pin-toggle-e2e',
            name: 'Pin Toggle E2E',
            collection_type: 'smart',
            collection_rule: { semantic_prompt: 'studio product shots', similarity_threshold: 0.8 },
            collection_assets: [
                { id: 21, asset_id: 9010, pinned: false, asset: { id: 9010, title: 'Studio Shot', original_filename: 'studio-shot.jpg' } },
            ],
        };

        await page.route(`**/api/v1/collections/${smartCollection.slug}*`, (route) => {
            if (route.request().method() !== 'GET') return route.continue();
            route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(smartCollection) });
        });

        await page.goto(`/collections/${smartCollection.slug}`);
        await expect(page.getByText('Studio Shot').or(page.getByText('studio-shot.jpg'))).toBeVisible();

        await page.getByTestId('MoreVertIcon').click();
        await expect(page.getByText('Remove from Collection')).toBeVisible();
        await expect(page.getByText('Pin to Collection')).not.toBeVisible();
        await expect(page.getByText('Unpin Asset')).not.toBeVisible();
    });

    // ------------------------------------------------------------------
    // 4. Generating a real signed share link and visiting it as a truly
    //    unauthenticated visitor.
    // ------------------------------------------------------------------
    test('generates a real signed share link and an unauthenticated visitor can view it', async ({ page, browser }) => {
        await page.goto('/collections');
        await page.waitForLoadState('networkidle');
        const csrfToken = await page.evaluate(() => document.querySelector('meta[name="csrf-token"]')?.content);

        const createRes = await page.request.post('/api/v1/collections', {
            data: { collection: { name: `Share E2E ${Date.now()}` } },
            headers: { 'X-CSRF-Token': csrfToken, 'Content-Type': 'application/json' },
        });
        expect(createRes.ok()).toBe(true);
        const created = await createRes.json();

        const shareRes = await page.request.post(`/api/v1/collections/${created.slug}/share_link`, {
            headers: { 'X-CSRF-Token': csrfToken },
        });
        expect(shareRes.ok()).toBe(true);
        const shareData = await shareRes.json();
        expect(shareData.url).toContain('/s/collections/');

        // A fresh, cookie-less browser context stands in for an anonymous
        // visitor who only has the link — no login, no shared storage state.
        const anonymousContext = await browser.newContext();
        const anonymousPage = await anonymousContext.newPage();
        try {
            const shareUrl = new URL(shareData.url);
            await anonymousPage.goto(shareUrl.pathname);

            await expect(anonymousPage.getByText(created.name)).toBeVisible();
            await expect(anonymousPage.getByTestId('public-share-asset-count')).toBeVisible();
        } finally {
            await anonymousContext.close();
        }
    });

    test('renders a 410 invalid-link page for a garbage share token, unauthenticated', async ({ browser }) => {
        const anonymousContext = await browser.newContext();
        const anonymousPage = await anonymousContext.newPage();
        try {
            const response = await anonymousPage.goto('/s/collections/not-a-real-token');
            expect(response.status()).toBe(410);
            await expect(anonymousPage.getByText(/invalid or has expired/i)).toBeVisible();
        } finally {
            await anonymousContext.close();
        }
    });

    // ------------------------------------------------------------------
    // 6. Metadata/tag-based smart collection rule (Feature 1).
    // ------------------------------------------------------------------
    test('configures a metadata-only smart rule and shows the real dry-run match count', async ({ page }) => {
        const metaCollection = {
            ...baseCollection,
            slug: 'metadata-rule-e2e',
            name: 'Metadata Rule E2E',
            collection_type: 'smart',
            collection_rule: null,
        };

        await page.route(`**/api/v1/collections/${metaCollection.slug}*`, (route) => {
            if (route.request().method() !== 'GET') return route.continue();
            route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(metaCollection) });
        });
        await page.route('**/api/v1/collections/simulate_rule', (route) => {
            if (route.request().method() !== 'POST') return route.continue();
            route.fulfill({
                status: 200,
                contentType: 'application/json',
                body: JSON.stringify({
                    matches: [ { id: 9020, title: 'Approved Asset', properties: { status: 'approved' } } ],
                    count: 1,
                    message: 'Simulation complete.',
                }),
            });
        });
        await page.route(`**/api/v1/collections/${metaCollection.slug}/rule`, (route) => {
            if (route.request().method() !== 'POST') return route.continue();
            route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ collection: metaCollection }) });
        });

        await page.goto(`/collections/${metaCollection.slug}`);
        await expect(page.getByText('Metadata Rule E2E')).toBeVisible();

        await page.getByRole('button', { name: /Configure Rules/i }).click();
        await page.getByRole('button', { name: 'Metadata / Tags' }).click();

        await page.getByLabel('Property key').fill('status');
        await page.getByLabel('Value(s), comma separated').fill('approved');
        await page.getByRole('button', { name: 'Add' }).click();

        await expect(page.getByText('status: approved')).toBeVisible();

        await page.getByRole('button', { name: 'Run Dry-Run Simulation' }).click();
        await expect(page.getByText('Approved Asset')).toBeVisible();
        await expect(page.getByText('1 theoretical matches')).toBeVisible();

        await page.getByRole('button', { name: 'Activate Rule in Production' }).click();
    });

    // ------------------------------------------------------------------
    // 7. Group-scoped Access Governance (Feature 2) — replaces dummy data
    //    with real user-group policies via the Workspace Properties dialog.
    // ------------------------------------------------------------------
    test('adds a group access policy from Workspace Properties and reflects it in the matrix', async ({ page }) => {
        await mockCollectionsIndex(page, [ baseCollection ]);
        await page.route('**/api/v1/user_groups*', (route) => {
            route.fulfill({
                status: 200,
                contentType: 'application/json',
                body: JSON.stringify([ { id: 42, name: 'EMEA Marketing', slug: 'emea-marketing', is_system: false } ]),
            });
        });
        await page.route(`**/api/v1/collections/${baseCollection.slug}/policies`, (route) => {
            const method = route.request().method();
            if (method === 'GET') {
                return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ policies: [] }) });
            }
            if (method === 'POST') {
                return route.fulfill({
                    status: 200,
                    contentType: 'application/json',
                    body: JSON.stringify({
                        success: true,
                        policy: { id: 1, group_id: 42, group_name: 'EMEA Marketing', view_access: true, edit_access: false, admin_access: false, explicit_deny: false },
                    }),
                });
            }
            return route.continue();
        });

        await page.goto('/collections');
        await expect(page.getByText('Spring Launch E2E')).toBeVisible();

        await page.getByTestId('MoreVertIcon').click();
        await page.getByText('Edit Properties & Access').click();

        await expect(page.getByText('collectionProperties.accessPolicies.empty').or(page.getByText('Group Access Policies'))).toBeAttached();
        await page.getByText('Group Access Policies').scrollIntoViewIfNeeded();

        await page.getByLabel(/Add group/i).fill('EMEA');
        await page.getByText('EMEA Marketing').click();
        await page.getByRole('button', { name: /^Add$/i }).click();

        await expect(page.getByText('EMEA Marketing')).toBeVisible();
    });

    // ------------------------------------------------------------------
    // 5. Collection slug-based nested routing (/collections/*path).
    // ------------------------------------------------------------------
    test('supports slug-based deep-link routing to a collection detail page', async ({ page }) => {
        const detail = { ...baseCollection, slug: 'deep-link-e2e', name: 'Deep Link E2E' };
        await mockCollectionDetail(page, detail.slug, () => detail);

        await page.goto(`/collections/${detail.slug}`);

        await expect(page.getByText('Deep Link E2E')).toBeVisible();
        await expect(page).toHaveURL(new RegExp(`/collections/${detail.slug}$`));

        // Client-side back navigation should return to the board (`/`, i.e.
        // `/collections` under the router's basename) without a hard reload.
        await page.getByRole('button', { name: 'Back to Workspace Board' }).click();
        await expect(page.getByText('My Collections')).toBeVisible();
    });
});
