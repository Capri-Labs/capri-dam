// E2E tests for the TDM & Storage Health screen at /admin/migrations/health.
// Prerequisites: Rails server running at E2E_BASE_URL with a seeded admin user.

const { test, expect } = require('./fixtures');

const EMAIL    = process.env.E2E_EMAIL    || 'admin@example.com';
const PASSWORD = process.env.E2E_PASSWORD || 'password123';

async function login(page) {
    await page.goto('/users/sign_in');
    await page.waitForSelector('input[autocomplete="email"]', { timeout: 15_000 });
    await page.fill('input[autocomplete="email"]', EMAIL);
    await page.fill('input[autocomplete="current-password"]', PASSWORD);
    await page.click('button[type="submit"], input[type="submit"]');
    await page.waitForLoadState('networkidle');
}

// Shared mock for the overview API — returns an empty-state scenario
const EMPTY_OVERVIEW = {
    storage:    { duplicates_prevented_tb: 0, active_used_tb: 0, orphaned_wasted_tb: 0, total_duplicates_blocked: 0, total_assets_committed: 0, total_assets_staged: 0, estimated_savings_gb: 0, estimated_savings_usd_mo: 0 },
    duplicates: { pending: 0, resolved: 0, dismissed: 0, total: 0 },
    connectors: { total: 0, active: 0, idle: 0, disabled: 0 },
    batches:    { total: 0, active: 0, completed: 0, failed: 0 },
    scan:       { status: 'idle', progress: {}, last_scan_at: null },
    debt_flags: [],
    generated_at: new Date().toISOString(),
};

const POPULATED_OVERVIEW = {
    ...EMPTY_OVERVIEW,
    storage:    { duplicates_prevented_tb: 0.0002, active_used_tb: 1.2, orphaned_wasted_tb: 0.08, total_duplicates_blocked: 42, total_assets_committed: 1200, total_assets_staged: 1500, estimated_savings_gb: 0.21, estimated_savings_usd_mo: 0.0048 },
    duplicates: { pending: 15, resolved: 30, dismissed: 5, total: 50 },
    connectors: { total: 3, active: 2, idle: 1, disabled: 0 },
    batches:    { total: 8, active: 1, completed: 6, failed: 1 },
    scan:       { status: 'completed', progress: { processed: 100, total: 100 }, last_scan_at: '2026-06-20T10:00:00Z' },
    debt_flags: [
        { type: 'duplicates', title: 'Confirmed Duplicate Asset Groups', description: 'desc', count: 15, impact: 'Medium', action_label: 'Resolve in Duplicate Manager', action_link: '/admin/duplicates', actionable: true, can_automate: false },
        { type: 'missing_metadata', title: 'Assets Missing Mandatory Metadata', description: 'desc', count: 200, impact: 'High', action_label: 'Run Pre-Flight Scans', action_link: '/admin/migrations/connectors', actionable: true, can_automate: true, remediation: 'missing_metadata' },
    ],
};

test.describe('TDM & Storage Health Dashboard E2E', () => {
    test.beforeEach(async ({ page }) => {
        await login(page);
    });

    // ── Smoke test ───────────────────────────────────────────────────────────
    test('health dashboard loads with the page title', async ({ page }) => {
        await page.goto('/admin/migrations/health');
        await page.waitForLoadState('networkidle');

        await expect(page.getByText(/tdm & storage health/i)).toBeVisible();
    });

    // ── Breadcrumb ───────────────────────────────────────────────────────────
    test('breadcrumb "Legacy Connectors" links to connectors page', async ({ page }) => {
        await page.goto('/admin/migrations/health');
        await page.waitForLoadState('networkidle');

        const link = page.getByRole('link', { name: /legacy connectors/i });
        await expect(link).toBeVisible();
        await expect(link).toHaveAttribute('href', /connectors/);
    });

    // ── Metric cards ─────────────────────────────────────────────────────────
    test('renders the 6 metric cards', async ({ page }) => {
        await page.route('/api/v1/data_health/overview', route => {
            route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(POPULATED_OVERVIEW) });
        });

        await page.goto('/admin/migrations/health');
        await page.waitForLoadState('networkidle');

        await expect(page.getByText(/pending duplicates/i)).toBeVisible();
        await expect(page.getByText(/storage saved/i)).toBeVisible();
        await expect(page.getByText(/monthly savings/i)).toBeVisible();
        await expect(page.getByText(/active connectors/i)).toBeVisible();
        await expect(page.getByText(/batches completed/i)).toBeVisible();
        await expect(page.getByText(/last repo scan/i)).toBeVisible();
    });

    // ── Tabs ─────────────────────────────────────────────────────────────────
    test('shows three tabs: Storage Overview, Connector Health, Debt Remediation', async ({ page }) => {
        await page.goto('/admin/migrations/health');
        await page.waitForLoadState('networkidle');

        await expect(page.getByRole('tab', { name: /storage overview/i })).toBeVisible();
        await expect(page.getByRole('tab', { name: /connector health/i })).toBeVisible();
        await expect(page.getByRole('tab', { name: /debt remediation/i })).toBeVisible();
    });

    // ── Storage composition bar ───────────────────────────────────────────────
    test('Storage Overview tab shows composition bar and pipeline summary', async ({ page }) => {
        await page.route('/api/v1/data_health/overview', route => {
            route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(POPULATED_OVERVIEW) });
        });

        await page.goto('/admin/migrations/health');
        await page.waitForLoadState('networkidle');

        await expect(page.getByText(/cloud storage composition/i)).toBeVisible();
        await expect(page.getByText(/migration pipeline summary/i)).toBeVisible();
        await expect(page.getByText(/active storage/i)).toBeVisible();
    });

    // ── Connector Health tab ─────────────────────────────────────────────────
    test('Connector Health tab loads and shows the health table when connectors exist', async ({ page }) => {
        const fakeConnectors = [
            {
                id: 1, name: 'AEM Production', provider_type: 'AEM', provider_label: 'Adobe Experience Manager (AEM)',
                status: 'active', assets_imported: 5000, last_sync: '2026-06-25T08:00:00Z',
                tdm_sanitation: true, batches_count: 3, health_score: 90,
                analysis_report: { total_found: 12450, missing_tags: 320, estimated_size_gb: 52.4 },
            },
        ];

        await page.route('/api/v1/data_health/connectors', route => {
            route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(fakeConnectors) });
        });

        await page.goto('/admin/migrations/health');
        await page.waitForLoadState('networkidle');
        await page.getByRole('tab', { name: /connector health/i }).click();
        await page.waitForLoadState('networkidle');

        await expect(page.getByText('AEM Production')).toBeVisible();
        await expect(page.getByText('12,450 assets found')).toBeVisible();
    });

    // ── Connector Health — empty state ────────────────────────────────────────
    test('Connector Health tab shows empty state when no connectors', async ({ page }) => {
        await page.route('/api/v1/data_health/connectors', route => {
            route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify([]) });
        });

        await page.goto('/admin/migrations/health');
        await page.waitForLoadState('networkidle');
        await page.getByRole('tab', { name: /connector health/i }).click();

        await expect(page.getByText(/no connectors configured/i)).toBeVisible();
    });

    // ── Debt Remediation tab ─────────────────────────────────────────────────
    test('Debt Remediation tab shows debt flags from the overview', async ({ page }) => {
        await page.route('/api/v1/data_health/overview', route => {
            route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(POPULATED_OVERVIEW) });
        });

        await page.goto('/admin/migrations/health');
        await page.waitForLoadState('networkidle');
        await page.getByRole('tab', { name: /debt remediation/i }).click();

        await expect(page.getByText('Confirmed Duplicate Asset Groups')).toBeVisible();
        await expect(page.getByText('Assets Missing Mandatory Metadata')).toBeVisible();
    });

    // ── Scan banner hidden when idle ──────────────────────────────────────────
    test('scan status banner is hidden when scan status is idle', async ({ page }) => {
        await page.route('/api/v1/data_health/overview', route => {
            route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(EMPTY_OVERVIEW) });
        });

        await page.goto('/admin/migrations/health');
        await page.waitForLoadState('networkidle');

        // The banner should not be visible
        await expect(page.getByText(/duplicate repository scan in progress/i)).not.toBeVisible();
    });

    // ── Scan banner shown when running ────────────────────────────────────────
    test('scan status banner is visible when a scan is running', async ({ page }) => {
        const runningOverview = {
            ...EMPTY_OVERVIEW,
            scan: { status: 'running', progress: { processed: 50, total: 200 }, last_scan_at: null },
        };

        await page.route('/api/v1/data_health/overview', route => {
            route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(runningOverview) });
        });

        await page.goto('/admin/migrations/health');
        await page.waitForLoadState('networkidle');

        await expect(page.getByText(/duplicate repository scan in progress/i)).toBeVisible();
    });

    // ── Manage Connectors button ─────────────────────────────────────────────
    test('"Connectors" button links to connectors screen', async ({ page }) => {
        await page.goto('/admin/migrations/health');
        await page.waitForLoadState('networkidle');

        const btn = page.getByRole('link', { name: /^connectors$/i }).first();
        await expect(btn).toBeVisible();
        await expect(btn).toHaveAttribute('href', /connectors/);
    });

    // ── Migration Pipeline button ────────────────────────────────────────────
    test('"Migration Pipeline" button links to ingestion screen', async ({ page }) => {
        await page.goto('/admin/migrations/health');
        await page.waitForLoadState('networkidle');

        const btn = page.getByRole('link', { name: /migration pipeline/i }).first();
        await expect(btn).toBeVisible();
        await expect(btn).toHaveAttribute('href', /ingestion/);
    });

    // ── Refresh button ────────────────────────────────────────────────────────
    test('"Refresh" button is visible and clickable', async ({ page }) => {
        await page.goto('/admin/migrations/health');
        await page.waitForLoadState('networkidle');

        const refreshBtn = page.getByRole('button', { name: /refresh/i });
        await expect(refreshBtn).toBeVisible();
        await refreshBtn.click();
    });
});

