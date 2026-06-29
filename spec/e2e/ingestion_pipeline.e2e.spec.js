// E2E tests for the Ingestion Pipeline screen at /admin/migrations/ingestion.
// Prerequisites: Rails server running at E2E_BASE_URL with a seeded admin user.

const { test, expect } = require('./fixtures');

const EMAIL    = process.env.E2E_EMAIL    || 'admin@example.com';
const PASSWORD = process.env.E2E_PASSWORD || 'password123';

async function login(page) {
    await page.goto('/users/sign_in');
    await page.fill('input[name="user[email]"]', EMAIL);
    await page.fill('input[name="user[password]"]', PASSWORD);
    await page.click('button[type="submit"], input[type="submit"]');
    await page.waitForLoadState('networkidle');
}

test.describe('Ingestion Pipeline Dashboard E2E', () => {
    test.beforeEach(async ({ page }) => {
        await login(page);
    });

    // ── Page-load smoke test ─────────────────────────────────────────────────
    test('ingestion dashboard loads and renders the page header', async ({ page }) => {
        await page.goto('/admin/migrations/ingestion');
        await page.waitForLoadState('networkidle');

        await expect(page.getByText('Migration Pipeline')).toBeVisible();
        await expect(page.getByRole('button', { name: /start migration/i })).toBeVisible();
    });

    // ── Metric cards ─────────────────────────────────────────────────────────
    test('renders the six metric stat cards', async ({ page }) => {
        await page.goto('/admin/migrations/ingestion');
        await page.waitForLoadState('networkidle');

        await expect(page.getByText(/total batches/i)).toBeVisible();
        await expect(page.getByText(/completed/i)).toBeVisible();
        await expect(page.getByText(/assets committed/i)).toBeVisible();
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
        await expect(page.getByRole('button', { name: /start migration/i })).toBeVisible();
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
        await expect(page.getByText('Bynder Review Batch')).toBeVisible();

        // The committed batch should show "View Report"
        await expect(page.getByRole('button', { name: /view report/i })).toBeVisible();

        // The review_needed batch should show "Audit"
        await expect(page.getByRole('button', { name: /audit/i })).toBeVisible();
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

