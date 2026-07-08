// E2E coverage for the Duplicate Manager screen (`/duplicates`,
// `app/javascript/components/Duplicates/**`), which previously had no
// dedicated spec of its own — its stat cards were only incidentally
// exercised by `spec/e2e/data_health.e2e.spec.js` (TDM & Storage Health
// dashboard), and `spec/e2e/search_and_duplicates_fixes.e2e.spec.js` only
// covers two "Go to Folder/asset" navigation regressions, not the core
// list/resolve/dismiss workflow. Covers the four scenarios requested:
//
//   1. Duplicate Manager page loads and lists existing duplicate groups.
//   2. Side-by-side resolution modal opens and shows both duplicate members.
//   3. Resolving a duplicate group (keep-all / delete-selected) updates its
//      status and removes it from the pending queue.
//   4. Dismissing a duplicate group excludes it from future (pending) prompts.
//
// All backend responses are mocked via route interception so these tests are
// deterministic and don't depend on live seed data.
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

function buildGroup(overrides = {}) {
    return {
        id: 'group-e2e-1',
        checksum: 'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2',
        status: 'pending',
        total_count: 2,
        assets: [
            {
                asset_id: 'asset-e2e-a', title: 'Hero-Shot.png', is_original: true,
                url: '/api/v1/assets/local/asset-e2e-a', content_type: 'image/png',
                folder_id: 'folder-e2e-9', folder_name: 'Marketing', file_size: 204_800,
                uploaded_at: '2026-01-05T00:00:00Z',
            },
            {
                asset_id: 'asset-e2e-b', title: 'Hero-Shot-copy.png', is_original: false,
                url: '/api/v1/assets/local/asset-e2e-b', content_type: 'image/png',
                folder_id: 'folder-e2e-9', folder_name: 'Marketing', file_size: 204_800,
                uploaded_at: '2026-01-06T00:00:00Z',
            },
        ],
        ...overrides,
    };
}

function mockStats(page, stats) {
    return page.route('**/api/v1/duplicate_groups/stats', (route) => {
        route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(stats) });
    });
}

// Serves the list endpoint per status filter. `groupsByStatus` maps a status
// key ("pending"/"resolved"/"dismissed"/"all") to the array that should be
// returned for that filter — callers can mutate the object between actions
// to simulate a group moving between queues.
function mockGroupsIndex(page, groupsByStatus) {
    return page.route('**/api/v1/duplicate_groups?status=**', (route) => {
        const url = new URL(route.request().url());
        const status = url.searchParams.get('status') || 'pending';
        const groups = groupsByStatus[status] || [];
        route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ total: groups.length, groups }) });
    });
}

function mockGroupDetail(page, group) {
    return page.route(`**/api/v1/duplicate_groups/${group.id}`, (route) => {
        if (route.request().method() !== 'GET') return route.continue();
        route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ group }) });
    });
}

test.describe('Duplicate Manager workspace E2E', () => {
    test.beforeEach(async ({ page }) => {
        await login(page);
    });

    // ------------------------------------------------------------------
    // 1. Duplicate Manager page loads and lists existing duplicate groups.
    // ------------------------------------------------------------------
    test('Duplicate Manager page loads and lists existing duplicate groups', async ({ page }) => {
        const group = buildGroup();
        await mockStats(page, { pending: 1, resolved: 0, dismissed: 0, total: 1 });
        await mockGroupsIndex(page, { pending: [ group ] });
        await mockGroupDetail(page, group);

        await page.goto('/duplicates');
        await page.waitForLoadState('networkidle');

        await expect(page.getByRole('heading', { name: 'Duplicate Manager' })).toBeVisible();
        await expect(page.getByText(/potential match/i).first()).toBeVisible();
        await expect(page.getByText(/2 identical files|identical files/i).first()).toBeVisible();
    });

    test('shows the empty state when there are no pending duplicate groups', async ({ page }) => {
        await mockStats(page, { pending: 0, resolved: 0, dismissed: 0, total: 0 });
        await mockGroupsIndex(page, { pending: [] });

        await page.goto('/duplicates');
        await page.waitForLoadState('networkidle');

        await expect(page.getByText(/no duplicate groups found/i)).toBeVisible();
    });

    // ------------------------------------------------------------------
    // 2. Side-by-side resolution modal opens and shows both duplicate
    //    members.
    // ------------------------------------------------------------------
    test('opens the side-by-side resolution modal and shows both duplicate members', async ({ page }) => {
        const group = buildGroup();
        await mockStats(page, { pending: 1, resolved: 0, dismissed: 0, total: 1 });
        await mockGroupsIndex(page, { pending: [ group ] });
        await mockGroupDetail(page, group);

        await page.goto('/duplicates');
        await page.waitForLoadState('networkidle');

        await page.getByText(/potential match/i).first().click();

        await expect(page.getByText('Resolve Duplicates')).toBeVisible();
        // Both members of the group must be visible side-by-side.
        await expect(page.getByText('Hero-Shot.png')).toBeVisible();
        await expect(page.getByText('Hero-Shot-copy.png')).toBeVisible();
        // The original should carry the "original" star badge tooltip target.
        await expect(page.getByText('Marketing').first()).toBeVisible();
    });

    // ------------------------------------------------------------------
    // 3. Resolving a duplicate group updates its status.
    // ------------------------------------------------------------------
    test('resolving a duplicate group by keeping all removes it from the pending queue', async ({ page }) => {
        const group = buildGroup();
        const groupsByStatus = { pending: [ group ], resolved: [] };

        await mockStats(page, { pending: 1, resolved: 0, dismissed: 0, total: 1 });
        await mockGroupsIndex(page, groupsByStatus);
        await mockGroupDetail(page, group);

        let resolvedPayload = null;
        await page.route(`**/api/v1/duplicate_groups/${group.id}/resolve`, (route) => {
            resolvedPayload = route.request().postDataJSON();
            const resolvedGroup = { ...group, status: 'resolved', resolution_action: 'kept_all' };
            groupsByStatus.pending = [];
            groupsByStatus.resolved = [ resolvedGroup ];
            route.fulfill({
                status: 200,
                contentType: 'application/json',
                body: JSON.stringify({ group: resolvedGroup, deleted_ids: [], message: 'Group resolved successfully.' }),
            });
        });

        await page.goto('/duplicates');
        await page.waitForLoadState('networkidle');

        await page.getByText(/potential match/i).first().click();
        await expect(page.getByText('Resolve Duplicates')).toBeVisible();

        await page.getByRole('button', { name: /keep all/i }).click();

        expect(resolvedPayload).toMatchObject({ action_type: 'kept_all' });

        // The modal closes and the group disappears from the pending queue.
        await expect(page.getByText('Resolve Duplicates')).toBeHidden();
        await expect(page.getByText(/no duplicate groups found/i)).toBeVisible();

        // Switching to the "Resolved" filter shows it there instead.
        await mockStats(page, { pending: 0, resolved: 1, dismissed: 0, total: 1 });
        await page.getByRole('button', { name: /resolved/i }).click();
        await expect(page.getByText(/potential match/i).first()).toBeVisible();
    });

    test('resolving a duplicate group by deleting the selected copy soft-deletes it', async ({ page }) => {
        const group = buildGroup();
        const groupsByStatus = { pending: [ group ], resolved: [] };

        await mockStats(page, { pending: 1, resolved: 0, dismissed: 0, total: 1 });
        await mockGroupsIndex(page, groupsByStatus);
        await mockGroupDetail(page, group);

        let resolvedPayload = null;
        await page.route(`**/api/v1/duplicate_groups/${group.id}/resolve`, (route) => {
            resolvedPayload = route.request().postDataJSON();
            const resolvedGroup = { ...group, status: 'resolved', resolution_action: 'deleted_duplicates' };
            groupsByStatus.pending = [];
            groupsByStatus.resolved = [ resolvedGroup ];
            route.fulfill({
                status: 200,
                contentType: 'application/json',
                body: JSON.stringify({ group: resolvedGroup, deleted_ids: [ 'asset-e2e-b' ], message: 'Group resolved successfully.' }),
            });
        });

        await page.goto('/duplicates');
        await page.waitForLoadState('networkidle');

        await page.getByText(/potential match/i).first().click();
        await expect(page.getByText('Resolve Duplicates')).toBeVisible();

        // Select the non-original copy, then delete it.
        await page.getByText('Hero-Shot-copy.png').click();
        await page.getByRole('button', { name: /delete/i }).click();
        await page.getByRole('button', { name: 'Confirm' }).click();

        expect(resolvedPayload).toMatchObject({ action_type: 'deleted_duplicates', asset_ids_to_delete: [ 'asset-e2e-b' ] });
        await expect(page.getByText('Resolve Duplicates')).toBeHidden();
        await expect(page.getByText(/no duplicate groups found/i)).toBeVisible();
    });

    // ------------------------------------------------------------------
    // 4. Dismissing a duplicate group excludes it from future prompts.
    // ------------------------------------------------------------------
    test('dismissing a duplicate group excludes it from future pending prompts', async ({ page }) => {
        const group = buildGroup();
        const groupsByStatus = { pending: [ group ], dismissed: [] };

        await mockStats(page, { pending: 1, resolved: 0, dismissed: 0, total: 1 });
        await mockGroupsIndex(page, groupsByStatus);
        await mockGroupDetail(page, group);

        let dismissCalled = false;
        await page.route(`**/api/v1/duplicate_groups/${group.id}/dismiss`, (route) => {
            dismissCalled = true;
            const dismissedGroup = { ...group, status: 'dismissed' };
            groupsByStatus.pending = [];
            groupsByStatus.dismissed = [ dismissedGroup ];
            route.fulfill({
                status: 200,
                contentType: 'application/json',
                body: JSON.stringify({ group: dismissedGroup, message: 'Group dismissed.' }),
            });
        });

        await page.goto('/duplicates');
        await page.waitForLoadState('networkidle');

        await page.getByText(/potential match/i).first().click();
        await expect(page.getByText('Resolve Duplicates')).toBeVisible();

        await page.getByLabel(/dismiss without action/i).click();

        expect(dismissCalled).toBe(true);
        await expect(page.getByText('Resolve Duplicates')).toBeHidden();

        // Re-fetching the pending queue (e.g. a manual refresh, or the next
        // time the page loads) must no longer surface the dismissed group.
        await mockStats(page, { pending: 0, resolved: 0, dismissed: 1, total: 1 });
        await page.getByRole('button', { name: /refresh/i }).click();
        await expect(page.getByText(/no duplicate groups found/i)).toBeVisible();
    });
});
