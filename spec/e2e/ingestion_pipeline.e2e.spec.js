// E2E tests for the Ingestion Pipeline screen at /admin/migrations/ingestion.
// Prerequisites: Rails server running at E2E_BASE_URL with a seeded admin user.

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

test.describe('Ingestion Pipeline Dashboard E2E', () => {
    test.beforeEach(async ({ page }) => {
        await login(page);
    });

    // ── Page-load smoke test ─────────────────────────────────────────────────
    test('ingestion dashboard loads and renders the page header', async ({ page }) => {
        await page.goto('/admin/migrations/ingestion');
        await page.waitForLoadState('networkidle');

        await expect(page.getByRole('heading', { name: 'Migration Pipeline' })).toBeVisible();
        await expect(page.getByRole('button', { name: /start migration/i }).first()).toBeVisible();
    });

    // ── Metric cards ─────────────────────────────────────────────────────────
    test('renders the six metric stat cards', async ({ page }) => {
        await page.goto('/admin/migrations/ingestion');
        await page.waitForLoadState('networkidle');

        await expect(page.getByText(/total batches/i)).toBeVisible();
        await expect(page.getByText(/completed/i)).toBeVisible();
        await expect(page.getByText('Assets Committed', { exact: true })).toBeVisible();
        await expect(page.getByText(/duplicates blocked/i)).toBeVisible();
        await expect(page.getByText(/storage saved/i)).toBeVisible();
        await expect(page.getByText(/cost savings/i)).toBeVisible();
    });

    // ── Pipeline phase banner ─────────────────────────────────────────────────
    test('shows the migration phases info banner', async ({ page }) => {
        await page.goto('/admin/migrations/ingestion');
        await page.waitForLoadState('networkidle');

        await expect(page.getByText(/migration phases/i)).toBeVisible();
        await expect(page.getByText(/metadata normalization/i)).toBeVisible();
    });

    // ── Breadcrumb navigation to connectors ─────────────────────────────────
    test('breadcrumb "Legacy Connectors" links to the connectors page', async ({ page }) => {
        await page.goto('/admin/migrations/ingestion');
        await page.waitForLoadState('networkidle');

        const connLink = page.getByRole('link', { name: /legacy connectors/i });
        await expect(connLink).toBeVisible();
        await expect(connLink).toHaveAttribute('href', /connectors/);
    });

    // ── Manage Connectors button ─────────────────────────────────────────────
    test('"Connectors" button navigates to connectors screen', async ({ page }) => {
        await page.goto('/admin/migrations/ingestion');
        await page.waitForLoadState('networkidle');

        await page.getByRole('link', { name: /connectors/i }).first().click();
        await page.waitForLoadState('networkidle');
        await expect(page).toHaveURL(/connectors/);
    });

    // ── Empty state ──────────────────────────────────────────────────────────
    test('shows empty state with CTA buttons when there are no batches', async ({ page }) => {
        // Intercept the API and return an empty batch list
        await page.route('/api/v1/ingestion_batches**', route => {
            route.fulfill({
                status:      200,
                contentType: 'application/json',
                body:        JSON.stringify({ batches: [], meta: { total: 0, page: 1, per_page: 50 } }),
            });
        });
        await page.route('/api/v1/ingestion_batches/stats', route => {
            route.fulfill({
                status:      200,
                contentType: 'application/json',
                body:        JSON.stringify({ total_batches: 0, active_batches: 0, completed_batches: 0, failed_batches: 0, total_assets_staged: 0, total_assets_committed: 0, total_duplicates_blocked: 0, total_errors: 0, estimated_storage_saved_gb: 0.0, estimated_cost_savings_usd: 0.0 }),
            });
        });

        await page.goto('/admin/migrations/ingestion');
        await page.waitForLoadState('networkidle');

        await expect(page.getByText(/no migration batches yet/i)).toBeVisible();
        await expect(page.getByRole('button', { name: /start migration/i }).first()).toBeVisible();
        await expect(page.getByRole('link',   { name: /configure connectors/i })).toBeVisible();
    });

    // ── New Migration wizard opens ────────────────────────────────────────────
    test('"Start Migration" button opens the wizard dialog', async ({ page }) => {
        await page.goto('/admin/migrations/ingestion');
        await page.waitForLoadState('networkidle');

        await page.getByRole('button', { name: /start migration/i }).first().click();
        await expect(page.getByRole('dialog')).toBeVisible();
        await expect(page.getByText(/start new migration/i)).toBeVisible();
        // Step 1 header
        await expect(page.getByText(/select source/i)).toBeVisible();
    });

    // ── Wizard closes on cancel ───────────────────────────────────────────────
    test('wizard can be closed via the Cancel button', async ({ page }) => {
        await page.goto('/admin/migrations/ingestion');
        await page.waitForLoadState('networkidle');

        await page.getByRole('button', { name: /start migration/i }).first().click();
        await expect(page.getByRole('dialog')).toBeVisible();

        await page.getByRole('button', { name: /cancel/i }).click();
        await expect(page.getByRole('dialog')).not.toBeVisible();
    });

    // ── Wizard destination step ───────────────────────────────────────────────
    test('wizard advances to the Select Destination step with a folder search box', async ({ page }) => {
        // Provide one active connector and a couple of folders so the wizard can advance.
        await page.route('/api/v1/system_connectors', route => {
            route.fulfill({
                status:      200,
                contentType: 'application/json',
                body:        JSON.stringify([
                    { id: 1, name: 'AEM Source', provider_type: 'aem', status: 'active', tdm_sanitation: true, assets_imported: 0 },
                ]),
            });
        });
        await page.route('/api/v1/folders', route => {
            route.fulfill({
                status:      200,
                contentType: 'application/json',
                body:        JSON.stringify({ folders: [
                    { id: 'f1', name: 'Marketing', path: '/Marketing', slug: 'marketing' },
                    { id: 'f2', name: 'Campaigns', path: '/Marketing/Campaigns', slug: 'campaigns' },
                ] }),
            });
        });

        await page.goto('/admin/migrations/ingestion');
        await page.waitForLoadState('networkidle');

        await page.getByRole('button', { name: /start migration/i }).first().click();
        await expect(page.getByRole('dialog')).toBeVisible();

        // Step 1 — select the source connector, then advance.
        await page.getByText('AEM Source').click();
        await page.getByRole('button', { name: /^next$/i }).click();

        // Step 2 — destination folder picker with a search box.
        await expect(page.getByText(/choose the folder where migrated assets/i)).toBeVisible();
        const search = page.getByPlaceholder(/search folders/i);
        await expect(search).toBeVisible();

        await search.fill('campaigns');
        await page.getByText('/Marketing/Campaigns').click();
        await expect(page.getByText(/assets will be migrated into/i)).toBeVisible();
    });

    // ── Wizard "Migrate Metadata" toggle ──────────────────────────────────────
    test('"Migrate Metadata" toggle defaults on and can be switched off before launch', async ({ page }) => {
        await page.route('/api/v1/system_connectors', route => {
            route.fulfill({
                status:      200,
                contentType: 'application/json',
                body:        JSON.stringify([
                    { id: 1, name: 'AEM Source', provider_type: 'aem', status: 'active', tdm_sanitation: true, assets_imported: 0 },
                ]),
            });
        });
        await page.route('/api/v1/folders', route => {
            route.fulfill({
                status:      200,
                contentType: 'application/json',
                body:        JSON.stringify({ folders: [
                    { id: 'f1', name: 'Marketing', path: '/Marketing', slug: 'marketing' },
                    { id: 'f2', name: 'Campaigns', path: '/Marketing/Campaigns', slug: 'campaigns' },
                ] }),
            });
        });

        let postedBody = null;
        await page.route('/api/v1/ingestion_batches', route => {
            if (route.request().method() === 'POST') {
                postedBody = route.request().postDataJSON();
                return route.fulfill({
                    status:      200,
                    contentType: 'application/json',
                    body:        JSON.stringify({ batch: { id: 999, name: 'Metadata Toggle Run' } }),
                });
            }
            return route.fulfill({
                status:      200,
                contentType: 'application/json',
                body:        JSON.stringify({ batches: [], meta: { total: 0, page: 1, per_page: 50 } }),
            });
        });

        await page.goto('/admin/migrations/ingestion');
        await page.waitForLoadState('networkidle');

        await page.getByRole('button', { name: /start migration/i }).first().click();
        await expect(page.getByRole('dialog')).toBeVisible();

        // Step 1 — select source, advance.
        await page.getByText('AEM Source').click();
        await page.getByRole('button', { name: /^next$/i }).click();

        // Step 2 — select destination, advance.
        await page.getByText('/Marketing/Campaigns').click();
        await page.getByRole('button', { name: /^next$/i }).click();

        // Step 3 — Configure Batch: Migrate Metadata switch defaults checked.
        const migrateMetadataSwitch = page.getByTestId('migrate-metadata-switch').locator('input[type="checkbox"]');
        await expect(migrateMetadataSwitch).toBeChecked();

        await migrateMetadataSwitch.click();
        await expect(migrateMetadataSwitch).not.toBeChecked();

        await page.getByRole('button', { name: /^next$/i }).click();

        // Step 4 — Summary reflects the opt-out.
        await expect(page.getByText(/disabled.*listing metadata only/i)).toBeVisible();

        await page.getByRole('button', { name: /initialize migration pipeline/i }).click();

        await expect.poll(() => postedBody?.ingestion_batch?.migrate_metadata).toBe(false);
    });

    // ── Batch table with data (mocked) ───────────────────────────────────────
    test('renders batch rows with status chips and actions', async ({ page }) => {
        const fakeBatches = [
            {
                id: 'uuid-1', name: 'AEM Migration — 2026-06-01', source_type: 'AEM', source_label: 'Adobe Experience Manager (AEM)',
                status: 'committed', progress_pct: 100, total_count: 500, processed_count: 500,
                committed_count: 480, duplicate_count: 15, error_count: 5,
                started_at: '2026-06-01T10:00:00Z', completed_at: '2026-06-01T14:00:00Z', created_at: '2026-06-01T10:00:00Z',
                connector_name: 'Production AEM', report_snapshot_id: 'snap-1',
            },
            {
                id: 'uuid-2', name: 'Bynder Review Batch', source_type: 'BYNDER', source_label: 'Bynder',
                status: 'review_needed', progress_pct: 90, total_count: 200, processed_count: 180,
                committed_count: 0, duplicate_count: 10, error_count: 2,
                started_at: '2026-06-15T08:00:00Z', completed_at: null, created_at: '2026-06-15T08:00:00Z',
                connector_name: 'Bynder EU', report_snapshot_id: null,
            },
        ];

        await page.route('/api/v1/ingestion_batches**', route => {
            if (route.request().url().includes('/stats')) return route.continue();
            route.fulfill({
                status:      200,
                contentType: 'application/json',
                body:        JSON.stringify({ batches: fakeBatches, meta: { total: 2, page: 1, per_page: 50 } }),
            });
        });

        await page.goto('/admin/migrations/ingestion');
        await page.waitForLoadState('networkidle');

        await expect(page.getByText('AEM Migration — 2026-06-01')).toBeVisible();
        await expect(page.getByText('Bynder Review Batch').first()).toBeVisible();

        // The committed batch should show "View Report"
        await expect(page.getByRole('button', { name: /view report/i })).toBeVisible();

        // The review_needed batch should show "Audit"
        await expect(page.getByRole('button', { name: 'Audit', exact: true })).toBeVisible();
    });

    // ── Batch Review audit: full migrated metadata panel ─────────────────────
    test('Audit workspace shows the migrated full metadata alongside Raw Legacy Attributes', async ({ page }) => {
        await page.route('/api/v1/ingestion_batches**', route => {
            const url = route.request().url();
            if (url.includes('/stats')) return route.continue();
            if (/\/ingestion_batches\/uuid-2(\?|$)/.test(url)) {
                return route.fulfill({
                    status:      200,
                    contentType: 'application/json',
                    body:        JSON.stringify({
                        batch: {
                            id: 'uuid-2', name: 'Bynder Review Batch', source_type: 'BYNDER',
                            status: 'review_needed', progress_pct: 90, total_count: 1, processed_count: 1,
                            committed_count: 0, duplicate_count: 0, error_count: 0,
                        },
                        items: [ {
                            id: 500,
                            original_filename: '715839_C_CascadeMilling_OrganicPancakeMix_S.psd',
                            status: 'ready_for_import',
                            file_size: 2048,
                            file_hash: 'abc123',
                            legacy_metadata: { title: '715839_C_CascadeMilling_OrganicPancakeMix_S.psd' },
                            full_metadata: {
                                'dc:title':       '715839_C_CascadeMilling_OrganicPancakeMix_S',
                                'dc:description': 'Organic Pancake Mix — full metadata from jcr:content/metadata.json',
                            },
                            clean_properties: { title: '715839_C_CascadeMilling_OrganicPancakeMix_S.psd' },
                        } ],
                        meta: { total: 1, page: 1, per_page: 50 },
                    }),
                });
            }
            return route.fulfill({
                status:      200,
                contentType: 'application/json',
                body:        JSON.stringify({ batches: [ {
                    id: 'uuid-2', name: 'Bynder Review Batch', source_type: 'BYNDER', source_label: 'Bynder',
                    status: 'review_needed', progress_pct: 90, total_count: 1, processed_count: 1,
                    committed_count: 0, duplicate_count: 0, error_count: 0,
                    started_at: '2026-06-15T08:00:00Z', completed_at: null, created_at: '2026-06-15T08:00:00Z',
                    connector_name: 'Bynder EU', report_snapshot_id: null,
                } ], meta: { total: 1, page: 1, per_page: 50 } }),
            });
        });

        await page.goto('/admin/migrations/ingestion');
        await page.waitForLoadState('networkidle');

        await page.getByRole('button', { name: 'Audit', exact: true }).click();
        await page.waitForLoadState('networkidle');

        await expect(page.getByText('715839_C_CascadeMilling_OrganicPancakeMix_S.psd').first()).toBeVisible();
        await expect(page.getByText('Raw Legacy Attributes')).toBeVisible();
        await expect(page.getByText('Metadata', { exact: true })).toBeVisible();
        await expect(page.getByText(/full metadata from jcr:content\/metadata\.json/)).toBeVisible();
    });

    // ── Status filter ─────────────────────────────────────────────────────────
    test('status filter dropdown is visible and selectable', async ({ page }) => {
        await page.goto('/admin/migrations/ingestion');
        await page.waitForLoadState('networkidle');

        await expect(page.getByLabel(/status/i)).toBeVisible();
    });

    // ── Refresh button ────────────────────────────────────────────────────────
    test('"Refresh" button is present and clickable', async ({ page }) => {
        await page.goto('/admin/migrations/ingestion');
        await page.waitForLoadState('networkidle');

        const refreshBtn = page.getByRole('button', { name: /refresh/i });
        await expect(refreshBtn).toBeVisible();
        await refreshBtn.click();
        // No error thrown = pass
    });
});

