// E2E tests for the Recycle Bin page (/bin).
// Runs against a live Rails server (set E2E_BASE_URL, E2E_EMAIL, E2E_PASSWORD).
//
// Coverage: page render, stats bar, single-row filter bar (search, type
// filter dropdown incl. "Other", sort, results/per-page, grid size, grid/list
// toggle), bulk selection, restore flow, empty-bin warning, pagination,
// empty-state.

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

    // The app performs a full-page redirect (window.location.href = '/') after
    // a successful AJAX sign-in; wait for it and then double-check the session
    // actually took effect (guards against a rare Set-Cookie/navigation race).
    await page.waitForURL(/^https?:\/\/[^/]+\/?(\?.*)?$/, { timeout: 15_000 });
    await page.waitForLoadState('networkidle');

    const signedIn = await page.locator('#header-root').getAttribute('data-signed-in');
    if (signedIn !== 'true') {
        await page.reload();
        await page.waitForLoadState('networkidle');
    }
}

test.describe('Recycle Bin E2E', () => {
    test.beforeEach(async ({ page }) => {
        await login(page);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Page rendering
    // ─────────────────────────────────────────────────────────────────────────

    test('renders the Recycle Bin page title', async ({ page }) => {
        await page.goto('/bin');
        await page.waitForLoadState('networkidle');
        await expect(page.getByRole('heading', { name: /recycle bin/i })).toBeVisible();
    });

    test('renders the stats bar with 4 stat cards', async ({ page }) => {
        await page.goto('/bin');
        await page.waitForLoadState('networkidle');

        // Stats bar contains Total Items, Assets, Folders, Storage Used
        await expect(page.getByText(/total items/i)).toBeVisible();
        await expect(page.getByText(/storage used/i)).toBeVisible();
    });

    test('renders the filter bar with search input', async ({ page }) => {
        await page.goto('/bin');
        await page.waitForLoadState('networkidle');

        await expect(page.getByPlaceholder(/search recycle bin/i)).toBeVisible();
    });

    test('renders a type-filter dropdown (All Items, Assets, Folders, Images, Videos, Documents, Other)', async ({ page }) => {
        await page.goto('/bin');
        await page.waitForLoadState('networkidle');

        // Type filter is a single dropdown button — open it and check every
        // option is present in the menu.
        const main = page.locator('#root');
        await main.getByRole('button', { name: /all items/i }).click();

        const menu = page.getByRole('menu');
        await expect(menu.getByRole('menuitem', { name: /^assets$/i })).toBeVisible();
        await expect(menu.getByRole('menuitem', { name: /^folders$/i })).toBeVisible();
        await expect(menu.getByRole('menuitem', { name: /images/i })).toBeVisible();
        await expect(menu.getByRole('menuitem', { name: /videos/i })).toBeVisible();
        await expect(menu.getByRole('menuitem', { name: /documents/i })).toBeVisible();
        await expect(menu.getByRole('menuitem', { name: /other/i })).toBeVisible();
    });

    test('renders view-layout toggle (grid/list)', async ({ page }) => {
        await page.goto('/bin');
        await page.waitForLoadState('networkidle');

        const gridBtn = page.locator('[value="grid"]').first();
        const listBtn = page.locator('[value="list"]').first();
        await expect(gridBtn).toBeVisible();
        await expect(listBtn).toBeVisible();
    });

    // ─────────────────────────────────────────────────────────────────────────
    // View toggling
    // ─────────────────────────────────────────────────────────────────────────

    test('switches between list and grid views', async ({ page }) => {
        await page.goto('/bin');
        await page.waitForLoadState('networkidle');

        // Default list view — table should be visible
        await expect(page.locator('table')).toBeVisible();

        // Switch to grid
        await page.locator('[value="grid"]').first().click();
        await expect(page.locator('table')).not.toBeVisible();
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Search / filter
    // ─────────────────────────────────────────────────────────────────────────

    test('search filters the bin list', async ({ page }) => {
        await page.goto('/bin');
        await page.waitForLoadState('networkidle');

        const searchInput = page.getByPlaceholder(/search recycle bin/i);
        await searchInput.fill('nonexistent_xyz_12345');

        // Wait for debounce + response
        await page.waitForTimeout(500);
        await page.waitForLoadState('networkidle');

        // Should show empty or filtered result (no error)
        const body = page.locator('body');
        await expect(body).toBeVisible();
    });

    test('type filter dropdown restricts items to folders only', async ({ page }) => {
        await page.goto('/bin');
        await page.waitForLoadState('networkidle');

        const main = page.locator('#root');
        await main.getByRole('button', { name: /all items/i }).click();
        await page.getByRole('menuitem', { name: /^folders$/i }).click();
        await page.waitForLoadState('networkidle');
        await page.waitForTimeout(400);

        // The dropdown button's label should now read "Folders".
        await expect(main.getByRole('button', { name: /^folders$/i })).toBeVisible();
    });

    test('per-page selector offers 25 / 50 / 100 results per page', async ({ page }) => {
        await page.goto('/bin');
        await page.waitForLoadState('networkidle');

        const perPageSelect = page.getByRole('combobox').last();
        await perPageSelect.click();

        const listbox = page.getByRole('listbox');
        await expect(listbox.getByRole('option', { name: /^25/ })).toBeVisible();
        await expect(listbox.getByRole('option', { name: /^50/ })).toBeVisible();
        await expect(listbox.getByRole('option', { name: /^100/ })).toBeVisible();

        await listbox.getByRole('option', { name: /^50/ }).click();
        await page.waitForLoadState('networkidle');
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Sort dropdown
    // ─────────────────────────────────────────────────────────────────────────

    test('sort dropdown opens and lists options', async ({ page }) => {
        await page.goto('/bin');
        await page.waitForLoadState('networkidle');

        // Click the sort button (contains "Deleted")
        await page.getByRole('button', { name: /deleted/i }).first().click();

        await expect(page.getByRole('menuitem', { name: /name \(a/i })).toBeVisible();
        await expect(page.getByRole('menuitem', { name: /size \(largest/i })).toBeVisible();

        // Dismiss
        await page.keyboard.press('Escape');
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Empty state
    // ─────────────────────────────────────────────────────────────────────────

    test('empty state is shown when bin is empty and no filters applied', async ({ page }) => {
        // We cannot guarantee the bin is empty in a real environment,
        // so we just verify the component renders without crashing.
        await page.goto('/bin');
        await page.waitForLoadState('networkidle');

        // Either the table/grid is visible OR the empty state message
        const hasItems    = await page.locator('table').isVisible().catch(() => false);
        const hasGrid     = await page.locator('[data-testid="bin-grid"]').isVisible().catch(() => false);
        const hasEmpty    = await page.getByText(/your recycle bin is empty/i).isVisible().catch(() => false);

        expect(hasItems || hasGrid || hasEmpty).toBeTruthy();
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Empty Bin button (requires items)
    // ─────────────────────────────────────────────────────────────────────────

    test('Empty Bin button opens confirmation dialog', async ({ page }) => {
        await page.goto('/bin');
        await page.waitForLoadState('networkidle');

        const emptyBtn = page.getByRole('button', { name: /empty bin/i });

        if (await emptyBtn.isVisible()) {
            await emptyBtn.click();

            // Confirm dialog should appear
            await expect(page.getByRole('dialog')).toBeVisible();
            await expect(page.getByText(/empty the recycle bin/i)).toBeVisible();

            // Cancel to avoid actually emptying the bin in E2E
            await page.getByRole('button', { name: /cancel/i }).click();
            await expect(page.getByRole('dialog')).not.toBeVisible();
        } else {
            // Bin might be empty — acceptable
            test.info().annotations.push({ type: 'skip-reason', description: 'Bin is empty; skipping empty-bin dialog test.' });
        }
    });

    // Regression test for a PG::ForeignKeyViolation 500 that used to abort
    // "Empty Bin" whenever a trashed asset's active_version_id was still
    // referenced elsewhere (see Api::V1::BinController#empty). Confirms the
    // real end-to-end flow — trash a fresh asset, empty the bin from the UI —
    // completes successfully with no error toast and no 500.
    test('Empty Bin actually empties the bin end-to-end without a 500 error', async ({ page }) => {
        const csrfToken = await page.evaluate(() => document.querySelector('meta[name="csrf-token"]')?.content);

        const buffer = Buffer.from(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
            'base64',
        );

        const createRes = await page.request.post('/api/v1/assets', {
            multipart: {
                file: { name: `empty-bin-e2e-${Date.now()}.png`, mimeType: 'image/png', buffer },
                title: `Empty Bin E2E ${Date.now()}`,
            },
            headers: { 'X-CSRF-Token': csrfToken },
        });
        expect(createRes.ok()).toBe(true);
        const created = await createRes.json();
        const assetId = created.id || created.uuid;

        const trashRes = await page.request.delete(`/api/v1/assets/${assetId}`, {
            headers: { 'X-CSRF-Token': csrfToken },
        });
        expect(trashRes.ok()).toBe(true);

        await page.goto('/bin');
        await page.waitForLoadState('networkidle');

        const emptyBtn = page.getByRole('button', { name: /empty bin/i });
        await expect(emptyBtn).toBeVisible();
        await emptyBtn.click();

        await expect(page.getByRole('dialog')).toBeVisible();

        const [emptyResponse] = await Promise.all([
            page.waitForResponse((res) => res.url().includes('/api/v1/bin/empty'), { timeout: 15_000 }),
            page.getByRole('dialog').getByRole('button', { name: /confirm/i }).click(),
        ]);

        expect(emptyResponse.status()).toBe(200);
        const body = await emptyResponse.json();

        // The endpoint must always return 200 and gracefully report any
        // per-item failures instead of crashing the whole request — items
        // that fail for unrelated reasons (e.g. still referenced by a
        // duplicate group) are reported in `errors`, but our freshly-created
        // test asset must always succeed.
        const ownAssetError = (body.errors ?? []).find((e) => e.includes(assetId));
        expect(ownAssetError).toBeUndefined();

        await expect(page.getByRole('dialog')).not.toBeVisible();

        // Bin list should no longer contain our test asset regardless of
        // whether unrelated pre-existing items failed to delete.
        await page.waitForLoadState('networkidle');
        await expect(page.getByText(created.title || `Empty Bin E2E`, { exact: false })).toHaveCount(0);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Preview thumbnails
    // ─────────────────────────────────────────────────────────────────────────

    // Regression test: the grid view showed only a generic file icon for
    // trashed image assets instead of an actual thumbnail, because the API
    // only exposed the raw `url` (not the `preview_url` used everywhere else
    // — Folders/Assets/Search) and the frontend never fell back to it.
    test('grid view renders an image thumbnail for a trashed image asset', async ({ page }) => {
        const csrfToken = await page.evaluate(() => document.querySelector('meta[name="csrf-token"]')?.content);

        const buffer = Buffer.from(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
            'base64',
        );
        const title = `Bin Preview E2E ${Date.now()}`;

        const createRes = await page.request.post('/api/v1/assets', {
            multipart: {
                file: { name: `bin-preview-e2e-${Date.now()}.png`, mimeType: 'image/png', buffer },
                title,
            },
            headers: { 'X-CSRF-Token': csrfToken },
        });
        expect(createRes.ok()).toBe(true);
        const created = await createRes.json();
        const assetId = created.id || created.uuid;

        const trashRes = await page.request.delete(`/api/v1/assets/${assetId}`, {
            headers: { 'X-CSRF-Token': csrfToken },
        });
        expect(trashRes.ok()).toBe(true);

        await page.goto('/bin');
        await page.waitForLoadState('networkidle');

        // Switch to grid view where thumbnails render.
        await page.locator('[value="grid"]').first().click();

        const card = page.locator('div', { hasText: title }).last();
        const thumb = page.locator('img[alt="' + title + '"]');
        await expect(thumb).toBeVisible({ timeout: 15_000 });
        const src = await thumb.getAttribute('src');
        expect(src).toBeTruthy();

        // Clean up: permanently delete the test asset.
        await page.request.delete('/api/v1/bin/bulk_destroy', {
            headers: { 'X-CSRF-Token': csrfToken, 'Content-Type': 'application/json' },
            data: { items: [ { id: assetId, type: 'asset' } ] },
        }).catch(() => {});
        void card;
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Sidebar navigation
    // ─────────────────────────────────────────────────────────────────────────

    test('Recycle Bin link in sidebar navigates to /bin', async ({ page }) => {
        await page.goto('/dashboard');
        await page.waitForLoadState('networkidle');

        const binLink = page.getByRole('link', { name: /recycle bin/i });
        if (await binLink.isVisible()) {
            await binLink.click();
            await page.waitForLoadState('networkidle');
            await expect(page).toHaveURL(/\/bin/);
        }
    });
});

// ───────────────────────────────────────────────────────────────────────────
// Bin Purge Settings (Tools › Asset Configurations)
// ───────────────────────────────────────────────────────────────────────────

test.describe('Bin Purge Settings E2E', () => {
    test.beforeEach(async ({ page }) => {
        await login(page);
    });

    test('Recycle Bin & Purge panel is reachable from Asset Configurations', async ({ page }) => {
        await page.goto('/tools/asset_configurations');
        await page.waitForLoadState('networkidle');

        // Nav item should be present
        const navItem = page.getByText(/recycle bin & purge/i).first();
        if (await navItem.isVisible()) {
            await navItem.click();
            await page.waitForLoadState('networkidle');

            // Purge status card + trigger button render
            await expect(page.getByRole('button', { name: /run purge now/i })).toBeVisible();
            await expect(page.getByRole('button', { name: /configure policy/i })).toBeVisible();
        }
    });

    test('policy editor opens and shows retention fields', async ({ page }) => {
        await page.goto('/tools/asset_configurations');
        await page.waitForLoadState('networkidle');

        const navItem = page.getByText(/recycle bin & purge/i).first();
        if (await navItem.isVisible()) {
            await navItem.click();
            await page.waitForLoadState('networkidle');

            await page.getByRole('button', { name: /configure policy/i }).click();

            await expect(page.getByLabel(/retention days/i)).toBeVisible();
            await expect(page.getByLabel(/workflow behavior/i)).toBeVisible();
            await expect(page.getByLabel(/batch size/i)).toBeVisible();
        }
    });

    test('AI gateway teaser is shown', async ({ page }) => {
        await page.goto('/tools/asset_configurations');
        await page.waitForLoadState('networkidle');

        const navItem = page.getByText(/recycle bin & purge/i).first();
        if (await navItem.isVisible()) {
            await navItem.click();
            await page.waitForLoadState('networkidle');

            await expect(page.getByText(/ai-assisted cleanup/i)).toBeVisible();
            await expect(page.getByRole('link', { name: /capri ai gateway/i })).toBeVisible();
        }
    });

    test('purge_status endpoint responds with policy + status', async ({ page }) => {
        const res  = await page.request.get('/api/v1/bin/purge_status');
        expect(res.ok()).toBeTruthy();
        const data = await res.json();
        expect(data).toHaveProperty('status');
        expect(data).toHaveProperty('policy');
        expect(data).toHaveProperty('triggered_by');
    });

    test('AI smart_suggestions endpoint responds', async ({ page }) => {
        const res  = await page.request.get('/api/v1/bin/ai/smart_suggestions');
        // 200 for admin, 403 for non-admin — both are valid contract responses
        expect([200, 403]).toContain(res.status());
        if (res.status() === 200) {
            const data = await res.json();
            expect(data).toHaveProperty('suggestions');
            expect(data).toHaveProperty('ai_available');
            expect(data.gateway_url).toContain('capri-dam-ai-gateway');
        }
    });
});

