const { test, expect } = require('./fixtures');
const { login } = require('./helpers/login');

function buildEntry(overrides = {}) {
  return {
    id: 101,
    status: 'pending_review',
    rejection_reason: 'TDM policy flagged a possible malware signature.',
    flagged_at: '2026-07-08T12:00:00Z',
    reviewed_at: null,
    review_notes: null,
    reviewed_by: null,
    system_connector: { id: 7, name: 'Dropbox Connector' },
    asset: {
      id: null,
      uuid: null,
      title: 'campaign-hero.png',
      status: null,
      trashed: false,
      preview_url: null,
      url: null,
      content_type: 'image/png',
      uploaded_by: 'admin@admin.com',
      uploaded_at: '2026-07-08T11:30:00Z',
    },
    original_payload: {
      asset: {
        name: 'campaign-hero.png',
        user_id: 1,
        properties: {
          content_type: 'image/png',
          size: 2048,
        },
      },
    },
    ...overrides,
  };
}

async function mockQuarantineRoutes(page, groupsByStatus, stats) {
  await page.route('**/api/v1/quarantined_assets/stats', (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify(typeof stats === 'function' ? stats() : stats),
    });
  });

  await page.route('**/api/v1/quarantined_assets?**', (route) => {
    const url = new URL(route.request().url());
    const status = url.searchParams.get('status') || 'pending_review';
    const items = groupsByStatus[status] || [];

    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        items,
        pagination: { total: items.length, page: 1, per_page: 25, pages: 1 },
      }),
    });
  });
}

test.describe('Quarantine review workspace', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
  });

  test('loads the quarantine page, lists entries, and opens the detail dialog', async ({ page }) => {
    const entry = buildEntry();

    await mockQuarantineRoutes(page, { pending_review: [ entry ] }, {
      pending_review: 1,
      resolved: 0,
      discarded: 0,
      total: 1,
    });

    await page.route(`**/api/v1/quarantined_assets/${entry.id}`, (route) => {
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ entry }),
      });
    });

    await page.goto('/admin/quarantine');
    await page.waitForLoadState('networkidle');

    await expect(page.getByRole('heading', { name: 'Quarantine Review' })).toBeVisible();
    await expect(page.getByText('campaign-hero.png', { exact: true })).toBeVisible();
    await expect(page.getByText(/possible malware signature/i)).toBeVisible();

    await page.getByRole('button', { name: 'Review', exact: true }).click();
    await expect(page.getByText('Quarantine entry details')).toBeVisible();
    await expect(page.getByText('Original payload')).toBeVisible();
  });

  test('release flow removes the entry from the pending queue and shows it in Released', async ({ page }) => {
    const entry = buildEntry();
    const releasedEntry = {
      ...entry,
      status: 'resolved',
      reviewed_at: '2026-07-09T08:00:00Z',
      reviewed_by: 'admin@admin.com',
      review_notes: 'Manual review approved release.',
      asset: {
        ...entry.asset,
        id: 501,
        uuid: 'released-asset-uuid',
        status: 'ready',
      },
    };

    const groupsByStatus = {
      pending_review: [ entry ],
      resolved: [],
      discarded: [],
      all: [ entry ],
    };

    await mockQuarantineRoutes(page, groupsByStatus, () => ({
      pending_review: groupsByStatus.pending_review.length,
      resolved: groupsByStatus.resolved.length,
      discarded: groupsByStatus.discarded.length,
      total: groupsByStatus.pending_review.length + groupsByStatus.resolved.length + groupsByStatus.discarded.length,
    }));

    let releaseCalled = false;
    await page.route(`**/api/v1/quarantined_assets/${entry.id}/release`, (route) => {
      releaseCalled = true;
      groupsByStatus.pending_review = [];
      groupsByStatus.resolved = [ releasedEntry ];
      groupsByStatus.all = [ releasedEntry ];

      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          entry: releasedEntry,
          message: 'Quarantined asset released.',
        }),
      });
    });

    await page.goto('/admin/quarantine');
    await page.waitForLoadState('networkidle');

    await page.getByRole('button', { name: 'Release', exact: true }).click();
    expect(releaseCalled).toBe(true);

    await expect(page.getByText('No quarantine entries found')).toBeVisible();

    await page.getByRole('button', { name: /Released/i }).click();
    await expect(page.getByText('campaign-hero.png', { exact: true })).toBeVisible();
  });

  test('discard flow removes the entry from quarantine and shows the asset in the Recycle Bin', async ({ page }) => {
    const entry = buildEntry();
    const discardedEntry = {
      ...entry,
      status: 'discarded',
      reviewed_at: '2026-07-09T09:00:00Z',
      reviewed_by: 'admin@admin.com',
      review_notes: 'Discarded after quarantine review.',
      asset: {
        ...entry.asset,
        id: 777,
        uuid: 'discarded-asset-uuid',
        status: 'rejected',
        trashed: true,
      },
    };

    const groupsByStatus = {
      pending_review: [ entry ],
      resolved: [],
      discarded: [],
      all: [ entry ],
    };

    await mockQuarantineRoutes(page, groupsByStatus, () => ({
      pending_review: groupsByStatus.pending_review.length,
      resolved: groupsByStatus.resolved.length,
      discarded: groupsByStatus.discarded.length,
      total: groupsByStatus.pending_review.length + groupsByStatus.resolved.length + groupsByStatus.discarded.length,
    }));

    let discardCalled = false;
    await page.route(`**/api/v1/quarantined_assets/${entry.id}/discard`, (route) => {
      discardCalled = true;
      groupsByStatus.pending_review = [];
      groupsByStatus.discarded = [ discardedEntry ];
      groupsByStatus.all = [ discardedEntry ];

      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          entry: discardedEntry,
          message: 'Quarantined asset discarded.',
        }),
      });
    });

    await page.route('**/api/v1/bin/stats', (route) => {
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          total_items: 1,
          total_assets: 1,
          total_folders: 0,
          total_size_bytes: 2048,
          retention_days: 30,
          oldest_deleted_at: '2026-07-09T09:00:00Z',
        }),
      });
    });

    await page.route('**/api/v1/bin?**', (route) => {
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          items: [
            {
              id: discardedEntry.asset.id,
              grid_id: 'asset-777',
              item_type: 'asset',
              media_type: 'image',
              name: discardedEntry.asset.title,
              url: null,
              preview_url: null,
              deleted_at: '2026-07-09T09:00:00Z',
              expires_at: '2026-08-08T09:00:00Z',
              size_human: '2 KB',
              original_path: '/marketing/campaign-hero.png',
            },
          ],
          pagination: { total: 1, page: 1, per_page: 25, pages: 1 },
          retention_days: 30,
        }),
      });
    });

    await page.goto('/admin/quarantine');
    await page.waitForLoadState('networkidle');

    await page.getByRole('button', { name: 'Discard', exact: true }).click();
    await page.getByRole('button', { name: 'Discard asset' }).click();
    expect(discardCalled).toBe(true);

    await expect(page.getByText('No quarantine entries found')).toBeVisible();

    await page.goto('/bin');
    await page.waitForLoadState('networkidle');
    await expect(page.getByRole('heading', { name: 'Recycle Bin' })).toBeVisible();
    await expect(page.getByText('campaign-hero.png', { exact: true })).toBeVisible();
  });
});
