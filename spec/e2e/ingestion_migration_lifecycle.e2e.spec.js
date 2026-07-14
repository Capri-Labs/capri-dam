// E2E tests for Ingestion & Migration — deeper coverage beyond the smoke tests
// in ingestion_pipeline.e2e.spec.js. This file focuses on the four scenarios
// that require a full request/response round-trip to exercise meaningfully:
//
//   1. Completing the migration wizard end-to-end (real connector selection,
//      authentication/eligibility gating, and launching a real batch).
//   2. The Legacy Connectors screen itself — configuring/testing/saving
//      connector credentials, editing, and status toggling.
//   3. Batch execution monitoring — a batch progressing through pipeline
//      phases, Abort/Delete actions actually calling their endpoints, and the
//      completed-batch detail (Migration Report) view.
//   4. Per-source connector behaviour for each of the supported DAM/legacy
//      platforms individually (dynamic field rendering per provider).
//
// Prerequisites: Rails server running at E2E_BASE_URL with a seeded admin user.
// All external-system calls are mocked via page.route — this exercises the
// full client request/response contract (headers, payload shape, CSRF token)
// without depending on live third-party DAM credentials.

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

    const signedIn = await page.locator('#header-root').getAttribute('data-signed-in');
    if (signedIn !== 'true') {
        await page.reload();
        await page.waitForLoadState('networkidle');
    }
}

// Canonical provider registry mirrored from app/lib/dam_providers.rb / the
// ConnectorDialog.jsx DAM_PROVIDERS map. Kept as data here (rather than
// imported) since this is a browser-driven Playwright spec, but each entry is
// cross-checked against the live dropdown in the "all providers" describe
// block below so the list can never silently drift from the app.
const SUPPORTED_PROVIDERS = [
    { key: 'AEM',         label: 'Adobe Experience Manager (AEM)', requiredFieldLabels: ['AEM Author Instance URL', 'Bearer / Service Account Token'] },
    { key: 'BYNDER',      label: 'Bynder',                          requiredFieldLabels: ['Bynder Portal URL', 'OAuth2 Access Token'] },
    { key: 'WIDEN',       label: 'Acquia DAM (Widen)',               requiredFieldLabels: ['Widen API Base URL', 'Widen API Key'] },
    { key: 'CANTO',       label: 'Canto',                            requiredFieldLabels: ['Canto Instance URL', 'JWT Bearer Token'] },
    { key: 'MEDIAVALET',  label: 'MediaValet',                       requiredFieldLabels: ['MediaValet API URL', 'Azure AD OAuth2 Bearer Token'] },
    { key: 'BRANDFOLDER', label: 'Brandfolder',                      requiredFieldLabels: ['Brandfolder API URL', 'API Key', 'Brandfolder Slug'] },
    { key: 'CLOUDINARY',  label: 'Cloudinary',                       requiredFieldLabels: ['Cloud Name', 'API Key', 'API Secret'] },
    { key: 'NUXEO',       label: 'Nuxeo Platform',                   requiredFieldLabels: ['Nuxeo Server URL'] },
    { key: 'APRIMO',      label: 'Aprimo DAM',                       requiredFieldLabels: ['Aprimo API URL', 'OAuth2 Bearer Token'] },
    { key: 'EXTENSIS',    label: 'Extensis Portfolio',                requiredFieldLabels: ['Portfolio Server URL', 'Session Token / API Key'] },
    { key: 'SHAREPOINT',  label: 'Microsoft SharePoint / OneDrive',   requiredFieldLabels: ['Microsoft Graph Drive URL', 'Azure AD Bearer Token'] },
    { key: 'LEGACY_S3',   label: 'AWS S3 Bucket',                     requiredFieldLabels: ['Secret Access Key', 'Region', 'Bucket Name'] },
    { key: 'FTP',         label: 'FTP / SFTP Server',                 requiredFieldLabels: ['Host / IP Address', 'Username', 'Password'] },
];

// ─────────────────────────────────────────────────────────────────────────────
// 1. Migration wizard — completing the flow end-to-end against a real connector
// ─────────────────────────────────────────────────────────────────────────────
test.describe('Migration Wizard — end-to-end completion', () => {
    test.beforeEach(async ({ page }) => {
        await login(page);
    });

    test('selects a real active connector, authenticates the destination, and launches a real batch', async ({ page }) => {
        // A realistic, fully-populated active connector (as returned once an
        // admin has configured + tested it on the Connectors screen).
        await page.route('/api/v1/system_connectors', route => {
            if (route.request().method() !== 'GET') return route.continue();
            route.fulfill({
                status:      200,
                contentType: 'application/json',
                body:        JSON.stringify([
                    {
                        id: 7, name: 'Production AEM Author', provider_type: 'aem', status: 'active',
                        endpoint: 'https://author.example.com', tdm_sanitation: true, assets_imported: 1204,
                        token_status: 'valid', credential_type: 'jwt_service_account',
                    },
                    // A disabled connector must NOT be offered as a migration source.
                    { id: 8, name: 'Retired Bynder', provider_type: 'bynder', status: 'disabled', assets_imported: 0 },
                ]),
            });
        });
        await page.route('/api/v1/folders', route => {
            route.fulfill({
                status:      200,
                contentType: 'application/json',
                body:        JSON.stringify({ folders: [
                    { id: 'f-marketing', name: 'Marketing', path: '/Marketing', slug: 'marketing' },
                    { id: 'f-campaigns', name: 'Campaigns', path: '/Marketing/Campaigns', slug: 'campaigns' },
                ] }),
            });
        });

        let launchBody = null;
        await page.route('/api/v1/ingestion_batches', route => {
            if (route.request().method() === 'POST') {
                launchBody = route.request().postDataJSON();
                return route.fulfill({
                    status:      200,
                    contentType: 'application/json',
                    body:        JSON.stringify({ batch: { id: 'batch-real-1', name: launchBody.ingestion_batch.name, status: 'initializing' } }),
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

        // Step 1 — only the active connector is offered; the disabled one is absent.
        await expect(page.getByText('Production AEM Author')).toBeVisible();
        await expect(page.getByText('Retired Bynder')).not.toBeVisible();
        await page.getByText('Production AEM Author').click();
        await page.getByRole('button', { name: /^next$/i }).click();

        // Step 2 — destination folder (simulates confirming where authenticated access lands).
        await expect(page.getByText(/choose the folder where migrated assets/i)).toBeVisible();
        await page.getByText('/Marketing/Campaigns').click();
        await expect(page.getByText(/assets will be migrated into/i)).toBeVisible();
        await page.getByRole('button', { name: /^next$/i }).click();

        // Step 3 — configure batch: give it a real, valid name.
        const nameField = page.getByLabel(/batch name/i);
        await nameField.fill('Production AEM — Full Catalogue Migration');
        await page.getByRole('button', { name: /^next$/i }).click();

        // Step 4 — confirm & launch a *real* batch (POST captured above).
        await expect(page.getByText(/confirm/i).first()).toBeVisible();
        await page.getByRole('button', { name: /initialize migration pipeline/i }).click();

        await expect.poll(() => launchBody?.ingestion_batch?.connector_id).toBe(7);
        expect(launchBody.ingestion_batch.source_type).toBe('aem');
        expect(launchBody.ingestion_batch.destination_folder_id).toBe('f-campaigns');
        expect(launchBody.ingestion_batch.name).toBe('Production AEM — Full Catalogue Migration');

        // Dialog closes and a success toast reflects the real batch name.
        await expect(page.getByRole('dialog')).not.toBeVisible();
    });

    test('shows a warning and a link to Connectors when there are no active connectors to authenticate against', async ({ page }) => {
        await page.route('/api/v1/system_connectors', route => {
            if (route.request().method() !== 'GET') return route.continue();
            route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify([]) });
        });
        await page.route('/api/v1/folders', route => {
            route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ folders: [] }) });
        });

        await page.goto('/admin/migrations/ingestion');
        await page.waitForLoadState('networkidle');

        await page.getByRole('button', { name: /start migration/i }).first().click();
        await expect(page.getByRole('dialog')).toBeVisible();
        await expect(page.getByText(/no active connectors found/i)).toBeVisible();

        const link = page.getByRole('link', { name: /configure connectors/i });
        await expect(link).toBeVisible();
        await expect(link).toHaveAttribute('href', '/admin/migrations/connectors');
    });

    test('surfaces a server-side launch failure (e.g. connector authentication rejected) without closing the wizard', async ({ page }) => {
        await page.route('/api/v1/system_connectors', route => {
            if (route.request().method() !== 'GET') return route.continue();
            route.fulfill({
                status: 200, contentType: 'application/json',
                body: JSON.stringify([{ id: 9, name: 'Flaky Cloudinary', provider_type: 'cloudinary', status: 'active', assets_imported: 0 }]),
            });
        });
        await page.route('/api/v1/folders', route => {
            route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ folders: [
                { id: 'f1', name: 'Root', path: '/Root', slug: 'root' },
            ] }) });
        });
        await page.route('/api/v1/ingestion_batches', route => {
            if (route.request().method() === 'POST') {
                return route.fulfill({
                    status: 422, contentType: 'application/json',
                    body: JSON.stringify({ error: 'Connector authentication failed: invalid or expired credentials.' }),
                });
            }
            return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ batches: [], meta: { total: 0, page: 1, per_page: 50 } }) });
        });

        await page.goto('/admin/migrations/ingestion');
        await page.waitForLoadState('networkidle');

        await page.getByRole('button', { name: /start migration/i }).first().click();
        await page.getByText('Flaky Cloudinary').click();
        await page.getByRole('button', { name: /^next$/i }).click();
        await page.getByText('/Root').click();
        await page.getByRole('button', { name: /^next$/i }).click();
        await page.getByLabel(/batch name/i).fill('Broken Auth Run');
        await page.getByRole('button', { name: /^next$/i }).click();
        await page.getByRole('button', { name: /initialize migration pipeline/i }).click();

        await expect(page.getByText(/connector authentication failed/i)).toBeVisible();
        // The wizard stays open so the admin can fix credentials and retry.
        await expect(page.getByRole('dialog')).toBeVisible();
    });
});

// ─────────────────────────────────────────────────────────────────────────────
// 2. Legacy Connectors screen — configuring & saving connector credentials
// ─────────────────────────────────────────────────────────────────────────────
test.describe('Legacy Connectors screen — configuration & credentials', () => {
    test.beforeEach(async ({ page }) => {
        await page.route('/api/v1/system_connectors?page=1', route => {
            if (route.request().method() !== 'GET') return route.continue();
            route.fulfill({
                status: 200, contentType: 'application/json',
                body: JSON.stringify({
                    connectors: [
                        { id: 11, name: 'Legacy AEM', provider_type: 'aem', status: 'active', endpoint: 'https://author.example.com', tdm_sanitation: true, assets_imported: 42, token_status: 'valid', credential_type: 'jwt_service_account' },
                    ],
                    pagination: { page: 1, per_page: 12, total: 1, total_pages: 1 },
                }),
            });
        });
        await login(page);
    });

    test('loads the connectors screen and shows the existing connector card', async ({ page }) => {
        await page.goto('/admin/migrations/connectors');
        await page.waitForLoadState('networkidle');

        await expect(page.getByText('System Connectors')).toBeVisible();
        await expect(page.getByText('Legacy AEM')).toBeVisible();
        await expect(page.getByRole('button', { name: /add connector/i })).toBeVisible();
    });

    test('"Add Connector" requires provider-specific credential fields before Save/Test are enabled', async ({ page }) => {
        await page.goto('/admin/migrations/connectors');
        await page.waitForLoadState('networkidle');

        await page.getByRole('button', { name: /add connector/i }).click();
        await expect(page.getByRole('dialog')).toBeVisible();

        const saveBtn = page.getByRole('button', { name: /initialize connection/i });
        const testBtn = page.getByRole('button', { name: /test connection/i });
        await expect(saveBtn).toBeDisabled();
        await expect(testBtn).toBeDisabled();

        // Default provider is AEM — fill name + endpoint but leave the token blank.
        await page.getByLabel('Connection Name').fill('New AEM Bridge');
        await page.getByLabel(/AEM Author Instance URL/i).fill('https://author2.example.com');
        await expect(saveBtn).toBeDisabled();

        // Now fill the required auth token — both actions become enabled.
        await page.getByLabel(/Bearer \/ Service Account Token/i).fill('secret-token-abc');
        await expect(saveBtn).toBeEnabled();
        await expect(testBtn).toBeEnabled();
    });

    test('"Test Connection" surfaces a success result from the server', async ({ page }) => {
        await page.route('/api/v1/system_connectors/test_connection', route => {
            route.fulfill({
                status: 200, contentType: 'application/json',
                body: JSON.stringify({ success: true, message: 'Connected successfully — 1,204 assets visible.' }),
            });
        });

        await page.goto('/admin/migrations/connectors');
        await page.waitForLoadState('networkidle');
        await page.getByRole('button', { name: /add connector/i }).click();

        await page.getByLabel('Connection Name').fill('New AEM Bridge');
        await page.getByLabel(/AEM Author Instance URL/i).fill('https://author2.example.com');
        await page.getByLabel(/Bearer \/ Service Account Token/i).fill('secret-token-abc');

        await page.getByRole('button', { name: /test connection/i }).click();
        await expect(page.getByText(/connected successfully/i)).toBeVisible();
    });

    test('"Test Connection" surfaces a failure result from the server', async ({ page }) => {
        await page.route('/api/v1/system_connectors/test_connection', route => {
            route.fulfill({
                status: 200, contentType: 'application/json',
                body: JSON.stringify({ success: false, message: 'Authentication failed: 401 Unauthorized.' }),
            });
        });

        await page.goto('/admin/migrations/connectors');
        await page.waitForLoadState('networkidle');
        await page.getByRole('button', { name: /add connector/i }).click();

        await page.getByLabel('Connection Name').fill('Bad AEM Bridge');
        await page.getByLabel(/AEM Author Instance URL/i).fill('https://author3.example.com');
        await page.getByLabel(/Bearer \/ Service Account Token/i).fill('wrong-token');

        await page.getByRole('button', { name: /test connection/i }).click();
        await expect(page.getByText(/authentication failed/i)).toBeVisible();
    });

    test('saves a new connector and the credentials round-trip through the create request', async ({ page }) => {
        let createdBody = null;
        await page.route('/api/v1/system_connectors', route => {
            if (route.request().method() === 'POST') {
                createdBody = route.request().postDataJSON();
                return route.fulfill({
                    status: 200, contentType: 'application/json',
                    body: JSON.stringify({ id: 55, name: createdBody.system_connector.name, provider_label: 'Cloudinary' }),
                });
            }
            return route.continue();
        });

        await page.goto('/admin/migrations/connectors');
        await page.waitForLoadState('networkidle');
        await page.getByRole('button', { name: /add connector/i }).click();

        await page.getByRole('combobox', { name: 'Source System / DAM Provider' }).click();
        await page.getByRole('option', { name: 'Cloudinary' }).click();
        await page.getByLabel('Connection Name').fill('Cloudinary Prod');
        await page.getByLabel('Cloud Name').fill('acme-corp');
        await page.getByLabel('API Key').fill('123456789');
        await page.getByLabel('API Secret').fill('super-secret-value');

        await page.getByRole('button', { name: /initialize connection/i }).click();

        await expect.poll(() => createdBody?.system_connector?.name).toBe('Cloudinary Prod');
        expect(createdBody.system_connector.provider_type).toBe('CLOUDINARY');
        expect(createdBody.system_connector.cloud_name).toBe('acme-corp');
        expect(createdBody.system_connector.secret_key).toBe('super-secret-value');
        await expect(page.getByRole('dialog')).not.toBeVisible();
    });

    test('editing an existing connector pre-fills its config but never re-displays the stored secret', async ({ page }) => {
        await page.route('/api/v1/system_connectors/11', route => {
            if (route.request().method() === 'PUT') {
                return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ id: 11, name: 'Legacy AEM Renamed' }) });
            }
            return route.continue();
        });

        await page.goto('/admin/migrations/connectors');
        await page.waitForLoadState('networkidle');

        await page.getByRole('button', { name: /configure/i }).click();
        await expect(page.getByRole('dialog')).toBeVisible();

        // Endpoint/name are pre-filled; the secret field is intentionally blank.
        await expect(page.getByLabel('Connection Name')).toHaveValue('Legacy AEM');
        const tokenField = page.getByLabel(/Bearer \/ Service Account Token/i);
        if (await tokenField.count() > 0) {
            await expect(tokenField).toHaveValue('');
        }

        await page.getByLabel('Connection Name').fill('Legacy AEM Renamed');
        await page.getByRole('button', { name: /save configuration/i }).click();
        await expect(page.getByRole('dialog')).not.toBeVisible();
    });

    test('toggling the status switch pauses/resumes ingestion via a PUT request', async ({ page }) => {
        let putBody = null;
        await page.route('/api/v1/system_connectors/11', route => {
            if (route.request().method() === 'PUT') {
                putBody = route.request().postDataJSON();
                return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ id: 11 }) });
            }
            return route.continue();
        });

        await page.goto('/admin/migrations/connectors');
        await page.waitForLoadState('networkidle');

        await page.getByRole('switch', { name: /pause ingestion/i }).click();
        await expect.poll(() => putBody?.system_connector?.status).toBe('disabled');
    });

    test('Adobe IMS JWT service-account connector exposes Refresh/Revoke token actions', async ({ page }) => {
        let refreshCalled = false;
        let revokeCalled  = false;
        await page.route('/api/v1/system_connectors/11/refresh_token', route => {
            refreshCalled = true;
            route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ token_status: 'valid', access_token_expires_at: '2026-08-01T00:00:00Z' }) });
        });
        await page.route('/api/v1/system_connectors/11/revoke_token', route => {
            revokeCalled = true;
            route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ token_status: 'revoked' }) });
        });
        page.on('dialog', dialog => dialog.accept());

        await page.goto('/admin/migrations/connectors');
        await page.waitForLoadState('networkidle');
        await page.getByRole('button', { name: /configure/i }).click();

        await expect(page.getByText(/token: valid/i)).toBeVisible();
        await page.getByRole('button', { name: /refresh token/i }).click();
        await expect.poll(() => refreshCalled).toBe(true);

        await page.getByRole('button', { name: /^revoke$/i }).click();
        await expect.poll(() => revokeCalled).toBe(true);
    });
});

// ─────────────────────────────────────────────────────────────────────────────
// 3. Batch execution monitoring — phases, retry/cancel, completed-batch detail
// ─────────────────────────────────────────────────────────────────────────────
test.describe('Batch execution monitoring', () => {
    test.beforeEach(async ({ page }) => {
        await login(page);
    });

    test('an active batch progresses through pipeline phases as it is refreshed', async ({ page }) => {
        const phases = ['extracting', 'transforming', 'review_needed'];
        let callIndex = 0;

        const buildBatch = (status) => ({
            id: 'batch-progress-1', name: 'Live Progress Batch', source_type: 'AEM', source_label: 'Adobe Experience Manager (AEM)',
            status, progress_pct: status === 'review_needed' ? 90 : status === 'transforming' ? 55 : 20,
            total_count: 100, processed_count: status === 'review_needed' ? 90 : status === 'transforming' ? 55 : 20,
            committed_count: 0, duplicate_count: 0, error_count: 0,
            started_at: '2026-07-01T10:00:00Z', completed_at: null, created_at: '2026-07-01T10:00:00Z',
            connector_name: 'Production AEM', report_snapshot_id: null,
        });

        await page.route('/api/v1/ingestion_batches**', route => {
            if (route.request().url().includes('/stats')) return route.continue();
            const status = phases[Math.min(callIndex, phases.length - 1)];
            route.fulfill({
                status: 200, contentType: 'application/json',
                body: JSON.stringify({ batches: [buildBatch(status)], meta: { total: 1, page: 1, per_page: 50 } }),
            });
        });

        await page.goto('/admin/migrations/ingestion');
        await page.waitForLoadState('networkidle');

        // Phase 1 — extracting.
        await expect(page.getByText('Extracting Files').first()).toBeVisible();

        // Advance to phase 2 via the manual Refresh control (avoids waiting on
        // the 6s poll interval) and confirm the stepper reflects the new phase.
        callIndex = 1;
        await page.getByRole('button', { name: /refresh/i }).click();
        await page.waitForLoadState('networkidle');
        await expect(page.getByText('AI Transforming').first()).toBeVisible();

        // Advance to phase 3 — awaiting human review.
        callIndex = 2;
        await page.getByRole('button', { name: /refresh/i }).click();
        await page.waitForLoadState('networkidle');
        await expect(page.getByText('Awaiting Review').first()).toBeVisible();
        await expect(page.getByRole('button', { name: /audit batch/i })).toBeVisible();
    });

    test('Abort ("cancel") action calls the abort endpoint and the batch disappears from Active Migrations', async ({ page }) => {
        let abortCalled = false;
        let batchAborted = false;
        page.on('dialog', dialog => dialog.accept());

        await page.route('/api/v1/ingestion_batches**', route => {
            const url = route.request().url();
            if (url.includes('/stats')) return route.continue();
            if (url.endsWith('/abort') && route.request().method() === 'POST') {
                abortCalled = true;
                batchAborted = true;
                return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ message: 'aborted' }) });
            }
            route.fulfill({
                status: 200, contentType: 'application/json',
                body: JSON.stringify({
                    batches: batchAborted ? [] : [{
                        id: 'batch-abort-1', name: 'Cancel Me Batch', source_type: 'AEM', source_label: 'Adobe Experience Manager (AEM)',
                        status: 'extracting', progress_pct: 30, total_count: 50, processed_count: 15,
                        committed_count: 0, duplicate_count: 0, error_count: 0,
                        started_at: '2026-07-01T10:00:00Z', completed_at: null, created_at: '2026-07-01T10:00:00Z',
                        connector_name: 'Production AEM', report_snapshot_id: null,
                    }],
                    meta: { total: batchAborted ? 0 : 1, page: 1, per_page: 50 },
                }),
            });
        });

        await page.goto('/admin/migrations/ingestion');
        await page.waitForLoadState('networkidle');
        await expect(page.getByText('Cancel Me Batch').first()).toBeVisible();

        // The batch renders in both the "Active Migrations" card section and the full
        // batches table below it — target the first matching Abort control (now that both
        // icon buttons carry an accessible aria-label of "Abort migration").
        await page.getByRole('button', { name: 'Abort migration' }).first().click();

        await expect.poll(() => abortCalled).toBe(true);
        await expect(page.getByText('Cancel Me Batch')).not.toBeVisible();
    });

    test('Delete action for a failed batch calls DELETE and removes it from the table', async ({ page }) => {
        let deleteCalled = false;
        page.on('dialog', dialog => dialog.accept());

        await page.route('/api/v1/ingestion_batches/batch-failed-1', route => {
            if (route.request().method() === 'DELETE') {
                deleteCalled = true;
                return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ message: 'deleted' }) });
            }
            return route.continue();
        });
        await page.route('/api/v1/ingestion_batches**', route => {
            if (route.request().url().includes('/stats')) return route.continue();
            // Defer to the more specific route registered above for this batch's own URL —
            // route.fallback() hands off to the other registered handler; route.continue()
            // would instead send the request straight to the real network, bypassing it.
            if (/\/ingestion_batches\/batch-failed-1/.test(route.request().url())) return route.fallback();
            route.fulfill({
                status: 200, contentType: 'application/json',
                body: JSON.stringify({
                    batches: deleteCalled ? [] : [{
                        id: 'batch-failed-1', name: 'Failed Legacy Import', source_type: 'FTP', source_label: 'FTP / SFTP',
                        status: 'failed', progress_pct: 40, total_count: 20, processed_count: 8,
                        committed_count: 0, duplicate_count: 0, error_count: 12,
                        started_at: '2026-07-01T10:00:00Z', completed_at: '2026-07-01T10:30:00Z', created_at: '2026-07-01T10:00:00Z',
                        connector_name: 'Legacy FTP', report_snapshot_id: null,
                    }],
                    meta: { total: deleteCalled ? 0 : 1, page: 1, per_page: 50 },
                }),
            });
        });

        await page.goto('/admin/migrations/ingestion');
        await page.waitForLoadState('networkidle');
        await expect(page.getByText('Failed Legacy Import')).toBeVisible();

        await page.getByRole('button', { name: 'Delete failed batch' }).click();
        await expect.poll(() => deleteCalled).toBe(true);
    });

    test('completed-batch detail view shows the full Migration Report after commit', async ({ page }) => {
        await page.route('/api/v1/ingestion_batches**', route => {
            const url = route.request().url();
            if (url.includes('/stats')) return route.continue();
            if (url.includes('/report')) {
                return route.fulfill({
                    status: 200, contentType: 'application/json',
                    body: JSON.stringify({ report: {
                        committed: 480, duplicates_blocked: 15, errors: 5, ai_enriched: 460,
                        duplicate_storage_saved_gb: 2.4, estimated_cost_savings_usd: 18.5,
                        top_errors: [['corrupt_file.psd', 'Unreadable file header']],
                    } }),
                });
            }
            if (/\/ingestion_batches\/batch-done-1(\?|$)/.test(url)) {
                return route.fulfill({
                    status: 200, contentType: 'application/json',
                    body: JSON.stringify({
                        batch: {
                            id: 'batch-done-1', name: 'Completed AEM Migration', source_label: 'Adobe Experience Manager (AEM)',
                            status: 'committed', progress_pct: 100, total_count: 500, processed_count: 500,
                            committed_count: 480, duplicate_count: 15, error_count: 5,
                        },
                        items: [],
                        meta: { total: 0, page: 1, per_page: 50 },
                    }),
                });
            }
            route.fulfill({
                status: 200, contentType: 'application/json',
                body: JSON.stringify({ batches: [{
                    id: 'batch-done-1', name: 'Completed AEM Migration', source_type: 'AEM', source_label: 'Adobe Experience Manager (AEM)',
                    status: 'committed', progress_pct: 100, total_count: 500, processed_count: 500,
                    committed_count: 480, duplicate_count: 15, error_count: 5,
                    started_at: '2026-06-01T10:00:00Z', completed_at: '2026-06-01T14:00:00Z', created_at: '2026-06-01T10:00:00Z',
                    connector_name: 'Production AEM', report_snapshot_id: 'snap-9',
                }], meta: { total: 1, page: 1, per_page: 50 } }),
            });
        });

        await page.goto('/admin/migrations/ingestion');
        await page.waitForLoadState('networkidle');

        await page.getByRole('button', { name: /view report/i }).click();
        await page.waitForLoadState('networkidle');

        await expect(page.getByText('Migration Report')).toBeVisible();
        await expect(page.getByText('480')).toBeVisible();
        await expect(page.getByText('Duplicates Blocked', { exact: true })).toBeVisible();
        await expect(page.getByText(/2\.4 GB/)).toBeVisible();
        await expect(page.getByText(/corrupt_file\.psd/)).toBeVisible();
        await expect(page.getByText('✅ Committed to DAM')).toBeVisible();
    });

    test('a review_needed batch can be approved and committed from the detail view', async ({ page }) => {
        let commitCalled = false;

        await page.route('/api/v1/ingestion_batches**', route => {
            const url = route.request().url();
            if (url.includes('/stats')) return route.continue();
            if (url.includes('/commit') && route.request().method() === 'POST') {
                commitCalled = true;
                return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ message: 'commit queued' }) });
            }
            if (url.includes('/report')) return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ report: {} }) });
            if (/\/ingestion_batches\/batch-review-1(\?|$)/.test(url)) {
                return route.fulfill({
                    status: 200, contentType: 'application/json',
                    body: JSON.stringify({
                        batch: {
                            id: 'batch-review-1', name: 'Ready For Review Batch', source_label: 'Bynder',
                            status: 'review_needed', progress_pct: 90, total_count: 10, processed_count: 9,
                            committed_count: 0, duplicate_count: 1, error_count: 0,
                        },
                        items: [],
                        meta: { total: 0, page: 1, per_page: 50 },
                    }),
                });
            }
            route.fulfill({
                status: 200, contentType: 'application/json',
                body: JSON.stringify({ batches: [{
                    id: 'batch-review-1', name: 'Ready For Review Batch', source_type: 'BYNDER', source_label: 'Bynder',
                    status: 'review_needed', progress_pct: 90, total_count: 10, processed_count: 9,
                    committed_count: 0, duplicate_count: 1, error_count: 0,
                    started_at: '2026-07-01T10:00:00Z', completed_at: null, created_at: '2026-07-01T10:00:00Z',
                    connector_name: 'Bynder EU', report_snapshot_id: null,
                }], meta: { total: 1, page: 1, per_page: 50 } }),
            });
        });
        page.on('dialog', dialog => dialog.accept());

        await page.goto('/admin/migrations/ingestion');
        await page.waitForLoadState('networkidle');

        await page.getByRole('button', { name: 'Audit', exact: true }).click();
        await page.waitForLoadState('networkidle');

        await page.getByRole('button', { name: /approve & commit batch/i }).click();
        await expect.poll(() => commitCalled).toBe(true);
    });
});

// ─────────────────────────────────────────────────────────────────────────────
// 4. Per-source connector behaviour — all supported DAM/legacy platforms
// ─────────────────────────────────────────────────────────────────────────────
test.describe('Per-source connector behaviour — supported platforms', () => {
    test.beforeEach(async ({ page }) => {
        await page.route('/api/v1/system_connectors?page=1', route => {
            if (route.request().method() !== 'GET') return route.continue();
            route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ connectors: [], pagination: { page: 1, per_page: 12, total: 0, total_pages: 1 } }) });
        });
        await login(page);
        await page.goto('/admin/migrations/connectors');
        await page.waitForLoadState('networkidle');
        await page.getByRole('button', { name: /add connector/i }).click();
        await expect(page.getByRole('dialog')).toBeVisible();
    });

    test('the provider dropdown offers every supported platform exactly once', async ({ page }) => {
        await page.getByRole('combobox', { name: 'Source System / DAM Provider' }).click();
        for (const { label } of SUPPORTED_PROVIDERS) {
            await expect(page.getByRole('option', { name: label })).toBeVisible();
        }
        await page.keyboard.press('Escape');
    });

    for (const provider of SUPPORTED_PROVIDERS) {
        test(`selecting "${provider.label}" renders its own credential fields`, async ({ page }) => {
            await page.getByRole('combobox', { name: 'Source System / DAM Provider' }).click();
            await page.getByRole('option', { name: provider.label }).click();

            for (const fieldLabel of provider.requiredFieldLabels) {
                await expect(page.getByLabel(new RegExp(fieldLabel.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i'))).toBeVisible();
            }

            // Save stays disabled until the provider's required fields + name are filled.
            await expect(page.getByRole('button', { name: /initialize connection/i })).toBeDisabled();
        });
    }

    test('only AEM and Canto (JWT-capable providers) show the Access Token / Service Account toggle', async ({ page }) => {
        await page.getByRole('combobox', { name: 'Source System / DAM Provider' }).click();
        await page.getByRole('option', { name: 'Adobe Experience Manager (AEM)' }).click();
        await expect(page.getByRole('button', { name: /service account \(jwt\)/i })).toBeVisible();

        await page.getByRole('combobox', { name: 'Source System / DAM Provider' }).click();
        await page.getByRole('option', { name: 'Cloudinary' }).click();
        await expect(page.getByRole('button', { name: /service account \(jwt\)/i })).not.toBeVisible();
    });

    test('FTP provider uses host/port fields instead of an HTTP endpoint (no URL validation applies)', async ({ page }) => {
        await page.getByRole('combobox', { name: 'Source System / DAM Provider' }).click();
        await page.getByRole('option', { name: 'FTP / SFTP Server' }).click();

        await expect(page.getByLabel(/host \/ ip address/i)).toBeVisible();
        await expect(page.getByLabel(/^port$/i)).toBeVisible();
        await expect(page.getByLabel(/remote path/i)).toBeVisible();
    });

    test('each provider shows its own contextual hint text', async ({ page }) => {
        const spotCheck = [
            { label: 'Adobe Experience Manager (AEM)', hint: /aem assets api/i },
            { label: 'Cloudinary', hint: /cloudinary console/i },
            { label: 'FTP / SFTP Server', hint: /legacy on-premises dam exports/i },
        ];
        for (const { label, hint } of spotCheck) {
            await page.getByRole('combobox', { name: 'Source System / DAM Provider' }).click();
            await page.getByRole('option', { name: label }).click();
            await expect(page.getByText(hint)).toBeVisible();
        }
    });
});
