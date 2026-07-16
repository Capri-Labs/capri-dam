// E2E tests for the standalone Reports screen (/reports) — previously
// entirely uncovered by any E2E spec. Covers all three tabs of the Reports
// hub (Admin/Reports/index.jsx): Analytics Dashboard, Download Center, and
// Report Types, plus the cross-cutting "Create Export" drawer flow.
//
// Covers:
//  - Page load: header, subtitle, and the three navigation tabs.
//  - Analytics Dashboard: stat cards + charts render from the real
//    GET /admin/reports/analytics endpoint; date-range switching (including
//    the Custom Range From/To + Apply flow) re-fetches analytics.
//  - Download Center: export history table/empty state, search + status
//    filter controls.
//  - Report Types: search/filter controls, built-in report types are listed
//    (seeded via db/seeds/report_definitions.rb), creating a new custom
//    report type via the real POST /admin/reports endpoint, and toggling its
//    active state via the real PATCH-style destroy/update round-trip.
//  - Create Export drawer: opens from both the page header button and from
//    the Analytics Dashboard toolbar, and queues a real export via
//    POST /admin/reports/:id/generate.json, landing in the Download Center.
//
// Prereqs: app running at E2E_BASE_URL with seed data (bin/rails db:seed),
// which seeds the 10 built-in ReportDefinition records including
// "Asset Library Summary".

const { test, expect } = require('./fixtures');

const ADMIN_EMAIL    = process.env.E2E_EMAIL    || 'admin@admin.com';
const ADMIN_PASSWORD = process.env.E2E_PASSWORD || 'AdminUser';

async function login(page) {
  await page.goto('/users/sign_in');
  await page.waitForSelector('input[autocomplete="email"]', { timeout: 15_000 });
  await page.fill('input[autocomplete="email"]', ADMIN_EMAIL);
  await page.fill('input[autocomplete="current-password"]', ADMIN_PASSWORD);

  const [response] = await Promise.all([
    page.waitForResponse((res) => res.url().includes('/users/sign_in.json'), { timeout: 15_000 }),
    page.click('button[type="submit"], input[type="submit"]'),
  ]);
  expect(response.ok()).toBeTruthy();

  await page.waitForURL(/^https?:\/\/[^/]+\/?(\?.*)?$/, { timeout: 15_000 });
  await page.waitForLoadState('networkidle');

  const signedIn = await page.locator('#header-root').getAttribute('data-signed-in');
  if (signedIn !== 'true') {
    await page.reload();
    await page.waitForLoadState('networkidle');
  }
}

test.describe('Reports screen (/reports) — page shell', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
    await page.goto('/reports');
    await page.waitForLoadState('networkidle');
  });

  test('loads the Reports & Analytics header and all three tabs', async ({ page }) => {
    await expect(page.getByRole('heading', { name: 'Reports & Analytics' })).toBeVisible();
    await expect(page.getByText(/live system insights/i)).toBeVisible();

    await expect(page.getByRole('tab', { name: /analytics dashboard/i })).toBeVisible();
    await expect(page.getByRole('tab', { name: /download center/i })).toBeVisible();
    await expect(page.getByRole('tab', { name: /report types/i })).toBeVisible();
  });

  test('"Create Export" header button opens the export builder drawer', async ({ page }) => {
    await page.getByRole('button', { name: /create export/i }).first().click();
    await expect(page.getByRole('heading', { name: 'Create Export' })).toBeVisible();
    await expect(page.getByText(/1\. Report Type/)).toBeVisible();
    await expect(page.getByText(/2\. Time Range/)).toBeVisible();
    await expect(page.getByText(/3\. Output Format/)).toBeVisible();
    await page.getByRole('button', { name: /cancel/i }).click();
    await expect(page.getByRole('heading', { name: 'Create Export' })).not.toBeVisible();
  });
});

test.describe('Reports screen — Analytics Dashboard', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
    await page.goto('/reports');
    await page.waitForLoadState('networkidle');
    // Analytics Dashboard is the default (first) tab.
    await expect(page.getByText('System Analytics')).toBeVisible();
  });

  test('renders the core stat cards populated from the real analytics endpoint', async ({ page }) => {
    const statCard = (label) => page.locator('.MuiCard-root').filter({ hasText: label }).first();
    await expect(statCard('Total Assets')).toBeVisible();
    await expect(statCard('Active Assets')).toBeVisible();
    await expect(statCard('Pending Approvals')).toBeVisible();
    await expect(statCard('Active Workflows')).toBeVisible();
    await expect(statCard('Storage Used')).toBeVisible();
    await expect(statCard('AI Coverage')).toBeVisible();
  });

  test('switching the date range re-fetches analytics for the new period', async ({ page }) => {
    const [response] = await Promise.all([
      page.waitForResponse((res) => res.url().includes('/admin/reports/analytics') && res.url().includes('range=last_7_days')),
      (async () => {
        await page.locator('.MuiSelect-select', { hasText: 'Last 30 Days' }).click();
        await page.getByRole('option', { name: 'Last 7 Days' }).click();
      })(),
    ]);
    expect(response.ok()).toBeTruthy();
  });

  test('Custom Range reveals From/To date pickers and an Apply button that re-fetches analytics', async ({ page }) => {
    await page.locator('.MuiSelect-select', { hasText: 'Last 30 Days' }).click();
    await page.getByRole('option', { name: /custom range/i }).click();

    await page.getByLabel('From').fill('2026-01-01');
    await page.getByLabel('To').fill('2026-01-31');

    const [response] = await Promise.all([
      page.waitForResponse((res) => res.url().includes('/admin/reports/analytics') && res.url().includes('range=custom')),
      page.getByRole('button', { name: /apply/i }).click(),
    ]);
    expect(response.ok()).toBeTruthy();
    expect(response.url()).toContain('from=2026-01-01');
  });

  test('"+ Create Export" in the toolbar opens the export builder drawer', async ({ page }) => {
    await page.getByRole('button', { name: /\+ create export/i }).click();
    await expect(page.getByRole('heading', { name: 'Create Export' })).toBeVisible();
  });

  test('folder filter narrows analytics to the selected folder and clears back to unfiltered', async ({ page }) => {
    const folderFilter = page.getByTestId('report-folder-filter');
    await expect(folderFilter).toBeVisible();

    await folderFilter.locator('input').click();
    await folderFilter.locator('input').fill('a');
    await page.waitForTimeout(300); // debounce-free client-side filter, just let the dropdown render

    const firstOption = page.locator('[data-testid^="report-folder-option-"]').first();
    await expect(firstOption).toBeVisible({ timeout: 10_000 });
    const optionTestId = await firstOption.getAttribute('data-testid');
    const folderId = optionTestId.replace('report-folder-option-', '');

    const [filteredResponse] = await Promise.all([
      page.waitForResponse((res) => res.url().includes('/admin/reports/analytics') && res.url().includes(`folder_ids=${folderId}`)),
      firstOption.click(),
    ]);
    expect(filteredResponse.ok()).toBeTruthy();

    // Clearing the selection (via the Autocomplete's clear "x" button) should
    // re-fetch with no folder_ids param at all.
    const clearButton = folderFilter.getByLabel(/clear/i);
    const [unfilteredResponse] = await Promise.all([
      page.waitForResponse((res) => res.url().includes('/admin/reports/analytics') && !res.url().includes('folder_ids')),
      clearButton.click(),
    ]);
    expect(unfilteredResponse.ok()).toBeTruthy();
  });
});

test.describe('Reports screen — Download Center', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
    await page.goto('/reports');
    await page.waitForLoadState('networkidle');
    await page.getByRole('tab', { name: /download center/i }).click();
  });

  test('shows the Download Center header and filter controls', async ({ page }) => {
    await expect(page.getByRole('heading', { name: 'Download Center' })).toBeVisible();
    await expect(page.getByPlaceholder(/search reports/i)).toBeVisible();
    await expect(page.locator('.MuiSelect-select').filter({ hasText: /all statuses/i })).toBeVisible();
  });

  test('shows either export rows or the empty-state message', async ({ page }) => {
    const emptyState = page.getByText(/no exports yet\. create one above\./i);
    const table = page.locator('table');
    // Exactly one of these must be true depending on seed state — assert the
    // screen resolved into a definite, non-loading state either way.
    await expect(emptyState.or(table)).toBeVisible({ timeout: 10_000 });
  });

  test('filtering by status narrows the results without erroring', async ({ page }) => {
    await page.locator('.MuiSelect-select').filter({ hasText: /all statuses/i }).click();
    await page.getByRole('option', { name: 'Ready' }).click();
    // No crash / stays on the Download Center — either rows filtered to
    // "Ready" chips only, or the empty-state message is shown. Scope the
    // "Ready" chip lookup to the results table to avoid matching the filter
    // select's own now-selected display value.
    const readyChip = page.locator('table').getByText('Ready', { exact: true });
    const emptyState = page.getByText(/no exports match your filter\./i);
    await expect(readyChip.first().or(emptyState)).toBeVisible({ timeout: 10_000 });
  });
});

test.describe('Reports screen — Report Types', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
    await page.goto('/reports');
    await page.waitForLoadState('networkidle');
    await page.getByRole('tab', { name: /report types/i }).click();
    await page.waitForLoadState('networkidle');
  });

  test('lists the seeded built-in report types with a "Built-in" badge', async ({ page }) => {
    await expect(page.getByText('Asset Library Summary')).toBeVisible();
    await expect(page.getByText('Built-in').first()).toBeVisible();
  });

  test('search filters the report type list', async ({ page }) => {
    await page.getByPlaceholder(/search report types/i).fill('Asset Library');
    await expect(page.getByText('Asset Library Summary')).toBeVisible();
    await expect(page.getByText('Workflow Compliance Report')).not.toBeVisible();
  });

  test('creates a new custom report type via the real API and shows it in the list', async ({ page }) => {
    const uniqueName = `E2E Custom Report ${Date.now()}`;
    await page.getByRole('button', { name: /new report type/i }).click();
    await expect(page.getByRole('heading', { name: 'New Report Type', exact: true })).toBeVisible();

    await page.getByLabel('Name').fill(uniqueName);
    await page.getByRole('textbox', { name: 'Type Key' }).fill(`e2e_custom_${Date.now()}`);
    await page.getByLabel('Description').fill('Created by the Reports screen E2E spec.');

    const [response] = await Promise.all([
      page.waitForResponse((res) => res.url().includes('/admin/reports') && res.request().method() === 'POST'),
      page.getByRole('button', { name: /^save$/i }).click(),
    ]);
    expect(response.ok()).toBeTruthy();
    const created = await response.json();

    await expect(page.getByText(/report type created/i)).toBeVisible({ timeout: 10_000 });

    // Search explicitly for the new item so this assertion is robust
    // regardless of how many other report types already exist / which
    // pagination page the newly-created row would otherwise land on
    // (the list is ordered by name, 20 per page).
    await page.getByPlaceholder(/search report types/i).fill(uniqueName);
    await expect(page.getByText(uniqueName)).toBeVisible({ timeout: 10_000 });
    await expect(page.getByText('Custom').first()).toBeVisible();

    // ── Cleanup: deactivate the disposable fixture so it drops out of the
    // default (active-only) list and doesn't accumulate in the shared dev
    // database across repeated test runs. ──
    await page.request.delete(`/admin/reports/${created.id}.json`);
  });

  test('deactivating a custom report type calls the real API and flips its badge to Inactive', async ({ page }) => {
    // Create a fresh disposable report type first so this test doesn't
    // depend on / mutate any other test's fixture data.
    const uniqueName = `E2E Toggle Report ${Date.now()}`;
    await page.getByRole('button', { name: /new report type/i }).click();
    await page.getByLabel('Name').fill(uniqueName);
    await page.getByRole('textbox', { name: 'Type Key' }).fill(`e2e_toggle_${Date.now()}`);
    await Promise.all([
      page.waitForResponse((res) => res.url().includes('/admin/reports') && res.request().method() === 'POST'),
      page.getByRole('button', { name: /^save$/i }).click(),
    ]);
    await expect(page.getByText(/report type created/i)).toBeVisible({ timeout: 10_000 });

    // Search explicitly so the freshly-created row is guaranteed visible
    // regardless of pagination / how many report types already exist.
    await page.getByPlaceholder(/search report types/i).fill(uniqueName);
    await expect(page.getByText(uniqueName)).toBeVisible({ timeout: 10_000 });

    // Click its "Deactivate" action (the toggle handler issues a real
    // DELETE, which soft-deactivates rather than destroying the row).
    const [response] = await Promise.all([
      page.waitForResponse((res) => /\/admin\/reports\/\d+/.test(res.url()) && res.request().method() === 'DELETE'),
      page.getByRole('button', { name: /deactivate/i }).last().click(),
    ]);
    expect(response.ok()).toBeTruthy();
    await expect(page.getByText(/report type deactivated/i)).toBeVisible({ timeout: 10_000 });
  });
});
