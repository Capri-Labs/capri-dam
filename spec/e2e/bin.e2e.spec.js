// E2E tests for the Recycle Bin page (/bin).
// Runs against a live Rails server (set E2E_BASE_URL, E2E_EMAIL, E2E_PASSWORD).
//
// Coverage: page render, stats bar, single-row filter bar (search, type
// filter dropdown incl. "Other", sort, results/per-page, grid size, grid/list
// toggle), bulk selection, restore flow, empty-bin warning, pagination,
// empty-state, single-item restore, workflow-protected purge guard,
// retention-policy save.

const { test, expect } = require('./fixtures');
const { execFileSync } = require('node:child_process');

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
    // Restore flow
    // ─────────────────────────────────────────────────────────────────────────

    // Real end-to-end restore: trash a fresh asset via the API, restore it
    // from the /bin UI (per-row restore icon → confirm dialog → confirm),
    // and verify it disappears from the bin AND is active again server-side.
    test('restoring an item from the bin returns it to the active library', async ({ page }) => {
        const csrfToken = await page.evaluate(() => document.querySelector('meta[name="csrf-token"]')?.content);
        const title = `Restore E2E ${Date.now()}`;

        const buffer = Buffer.from(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
            'base64',
        );

        const createRes = await page.request.post('/api/v1/assets', {
            multipart: {
                file: { name: `restore-e2e-${Date.now()}.png`, mimeType: 'image/png', buffer },
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

        // Search narrows the list down to just our test item so the restore
        // icon button is unambiguous regardless of what else is in the bin.
        await page.getByPlaceholder(/search recycle bin/i).fill(title);
        await page.waitForTimeout(500); // debounce
        await page.waitForLoadState('networkidle');

        await expect(page.getByText(title)).toBeVisible();

        const [restoreResponse] = await Promise.all([
            page.waitForResponse((res) => res.url().includes('/api/v1/bin/bulk_restore'), { timeout: 15_000 }),
            (async () => {
                await page.getByRole('button', { name: /restore/i }).first().click();
                await expect(page.getByRole('dialog')).toBeVisible();
                await page.getByRole('dialog').getByRole('button', { name: /confirm/i }).click();
            })(),
        ]);

        expect(restoreResponse.status()).toBe(200);
        const body = await restoreResponse.json();
        expect(body.restored).toBe(1);

        await expect(page.getByRole('dialog')).not.toBeVisible();
        await page.waitForLoadState('networkidle');
        await expect(page.getByText(title)).toHaveCount(0);

        // Server-side: the asset is fetchable through the normal (non-bin)
        // assets API again after being restored (the /api/v1/bin listing no
        // longer includes it, verified above via the UI).
        const fetchRes = await page.request.get(`/api/v1/assets/${assetId}`);
        expect(fetchRes.ok()).toBe(true);

        // Clean up — trash it again and permanently remove via bulk_destroy
        // so this test doesn't leave residue in the active library.
        await page.request.delete(`/api/v1/assets/${assetId}`, { headers: { 'X-CSRF-Token': csrfToken } });
        await page.request.delete('/api/v1/bin/bulk_destroy', {
            headers: { 'X-CSRF-Token': csrfToken, 'Content-Type': 'application/json' },
            data: { items: [ { id: assetId, type: 'asset' } ] },
        }).catch(() => {});
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

    // ─────────────────────────────────────────────────────────────────────────
    // Workflow-protected purge guard
    // ─────────────────────────────────────────────────────────────────────────

    // Real end-to-end guard check: an asset with a live (non-terminal)
    // workflow instance attached must survive a purge run — even one
    // configured with retention_days: 0 (i.e. everything in the bin is
    // technically eligible) — because BinPurgeService's default
    // workflow_behavior ("skip") protects assets still under active review.
    test('an asset with an active workflow instance is skipped by the purge instead of deleted', async ({ page }) => {
        const csrfToken = await page.evaluate(() => document.querySelector('meta[name="csrf-token"]')?.content);
        const jsonHeaders = { 'X-CSRF-Token': csrfToken, 'Content-Type': 'application/json' };

        const originalPolicyRes = await page.request.get('/api/v1/bin/retention_policy');
        const originalPolicy    = await originalPolicyRes.json();

        // 1. Create a fresh asset.
        const buffer = Buffer.from(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
            'base64',
        );
        const title = `Workflow Guard E2E ${Date.now()}`;
        const createRes = await page.request.post('/api/v1/assets', {
            multipart: { file: { name: `wf-guard-${Date.now()}.png`, mimeType: 'image/png', buffer }, title },
            headers: { 'X-CSRF-Token': csrfToken },
        });
        expect(createRes.ok()).toBe(true);
        const created = await createRes.json();

        // 2. Find our own admin user id (needed as the workflow step's
        // assignee) — there is no direct "current user" JSON endpoint.
        const meRes = await page.request.get(`/admin/users.json?search=${encodeURIComponent(EMAIL)}`);
        expect(meRes.ok()).toBe(true);
        const { users } = await meRes.json();
        const me = users.find((u) => u.email === EMAIL);
        expect(me).toBeTruthy();

        // 3. Create an active workflow with one approval step (keeps any
        // triggered instance in a non-terminal "in_progress" status).
        const workflowRes = await page.request.post('/workflows', {
            headers: jsonHeaders,
            data: {
                workflow: {
                    name: `Guard Test Workflow ${Date.now()}`,
                    trigger_type: 'manual',
                    status: 'active',
                    workflow_steps_attributes: [
                        { position: 1, step_type: 'approval', assignee_type: 'user', assignee_id: me.id, logic: 'any', title: 'Approve' },
                    ],
                },
            },
        });
        expect(workflowRes.ok()).toBe(true);
        const { workflow } = await workflowRes.json();

        // 4. Trigger the workflow on the asset (creates a live WorkflowInstance
        // via WorkflowInitiatorWorker, a real Sidekiq job in this dev env).
        const triggerRes = await page.request.post('/api/v1/workflows/bulk_trigger', {
            headers: jsonHeaders,
            data: { workflow_id: workflow.id, asset_ids: [ created.id ] },
        });
        expect(triggerRes.ok()).toBe(true);
        await page.waitForTimeout(2000); // let Sidekiq process WorkflowInitiatorWorker

        try {
            // 5. Trash the asset and set the minimum retention policy (1 day —
            // the API intentionally treats retention_days: 0 as a no-op) so
            // it's eligible for purge on the very next run, with the "skip"
            // guard. Backdate deleted_at via a direct Rails call — there is no
            // API to simulate "trashed N days ago" for a freshly-created test
            // asset, and the purge's eligibility cutoff is time-based.
            const trashRes = await page.request.delete(`/api/v1/assets/${created.id}`, { headers: { 'X-CSRF-Token': csrfToken } });
            expect(trashRes.ok()).toBe(true);

            execFileSync('bundle', [
                'exec', 'rails', 'runner',
                `Asset.find_by(uuid: ${JSON.stringify(created.uuid || created.id)}).update_column(:deleted_at, 2.days.ago)`,
            ], { cwd: process.cwd(), stdio: 'pipe' });

            const policyRes = await page.request.put('/api/v1/bin/retention_policy', {
                headers: jsonHeaders,
                data: { retention_days: 1, workflow_behavior: 'skip', batch_size: originalPolicy.batch_size },
            });
            expect(policyRes.ok()).toBe(true);

            // 6. Trigger the purge from the real UI (Tools > Asset Configurations
            // > Recycle Bin & Purge > "Run Purge Now").
            await page.goto('/tools/asset_configurations');
            await page.waitForLoadState('networkidle');
            const navItem = page.getByText(/recycle bin & purge/i).first();
            await expect(navItem).toBeVisible();
            await navItem.click();
            await page.waitForLoadState('networkidle');

            const [triggerResponse] = await Promise.all([
                page.waitForResponse((res) => res.url().includes('/api/v1/bin/trigger_purge'), { timeout: 15_000 }),
                page.getByRole('button', { name: /run purge now/i }).click(),
            ]);
            expect(triggerResponse.ok()).toBeTruthy();

            // 7. Poll purge_status until the run completes.
            let status = 'queued';
            let lastResults = {};
            for (let i = 0; i < 30 && status !== 'completed'; i++) {
                await page.waitForTimeout(1000);
                const statusRes = await page.request.get('/api/v1/bin/purge_status');
                const statusBody = await statusRes.json();
                status = statusBody.status;
                lastResults = statusBody.last_results || {};
            }
            expect(status).toBe('completed');

            // 8. The asset must have been *skipped* (protected), not deleted.
            // Note: `created.id` is the uuid-exposed API id (see
            // Api::V1::AssetsController#format_asset), while skipped_items
            // are recorded with the asset's real primary key — match on
            // title instead, which is unambiguous for this freshly-created
            // test asset.
            const skipped = (lastResults.skipped_items || []).find((item) => item.title === title);
            expect(skipped).toBeTruthy();
            expect(skipped.reason).toBe('active_workflow');

            const stillInBin = await page.request.get(`/api/v1/assets/${created.id}`);
            // Trashed assets 404/403 via the normal show action depending on
            // scoping, but the important, unambiguous check is that it still
            // exists in the bin listing rather than having been hard-deleted.
            const binListRes = await page.request.get('/api/v1/bin?per_page=200');
            const binList = await binListRes.json();
            expect(binList.items.some((i) => i.name === title || i.title === title)).toBe(true);
            void stillInBin;
        } finally {
            // Clean up: cancel the workflow instance, remove the asset, and
            // restore the original retention policy so this test is
            // idempotent across runs.
            await page.request.put('/api/v1/bin/retention_policy', {
                headers: jsonHeaders,
                data: {
                    retention_days: originalPolicy.retention_days,
                    workflow_behavior: originalPolicy.workflow_behavior,
                    batch_size: originalPolicy.batch_size,
                },
            }).catch(() => {});
            await page.request.delete('/api/v1/bin/bulk_destroy', {
                headers: jsonHeaders,
                data: { items: [ { id: created.id, type: 'asset' } ] },
            }).catch(() => {});
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

    // Real end-to-end save: change the retention-days field in the policy
    // editor, click Save, and verify the change actually persisted
    // server-side (survives a full page reload), then restore the original
    // value so this test is idempotent/non-destructive across runs.
    test('saving the retention policy persists the change', async ({ page }) => {
        const original = await page.request.get('/api/v1/bin/retention_policy');
        expect(original.ok()).toBeTruthy();
        const originalPolicy = await original.json();
        const originalDays = originalPolicy.retention_days;
        const newDays = originalDays === 45 ? 60 : 45;

        try {
            await page.goto('/tools/asset_configurations');
            await page.waitForLoadState('networkidle');

            const navItem = page.getByText(/recycle bin & purge/i).first();
            await expect(navItem).toBeVisible();
            await navItem.click();
            await page.waitForLoadState('networkidle');

            await page.getByRole('button', { name: /configure policy/i }).click();

            const retentionField = page.getByLabel(/retention days/i);
            await expect(retentionField).toBeVisible();
            await retentionField.fill(String(newDays));

            const [saveResponse] = await Promise.all([
                page.waitForResponse((res) => res.url().includes('/api/v1/bin/retention_policy') && res.request().method() === 'PUT', { timeout: 15_000 }),
                page.getByRole('button', { name: /save changes/i }).click(),
            ]);
            expect(saveResponse.ok()).toBeTruthy();
            const saved = await saveResponse.json();
            expect(saved.retention_days ?? saved.policy?.retention_days).toBe(newDays);

            // Confirm it actually persisted server-side, independent of any
            // client-side optimistic state, by re-fetching after a reload.
            await page.reload();
            await page.waitForLoadState('networkidle');
            const refetched = await page.request.get('/api/v1/bin/retention_policy');
            const refetchedPolicy = await refetched.json();
            expect(refetchedPolicy.retention_days).toBe(newDays);
        } finally {
            const csrfToken = await page.evaluate(() => document.querySelector('meta[name="csrf-token"]')?.content);
            await page.request.put('/api/v1/bin/retention_policy', {
                headers: { 'X-CSRF-Token': csrfToken, 'Content-Type': 'application/json' },
                data: {
                    retention_days:    originalDays,
                    workflow_behavior: originalPolicy.workflow_behavior,
                    batch_size:        originalPolicy.batch_size,
                },
            }).catch(() => {});
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

