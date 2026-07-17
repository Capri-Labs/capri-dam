// Real end-to-end E2E test for the Asset Version History diff view
// (`app/javascript/components/Folders/AssetVersionsTab.jsx`).
//
// Unlike `spec/e2e/folders_workspace_coverage.e2e.spec.js`'s "Versions tab
// can compare two versions with the diff overlay controls" test (which
// exercises the UI mechanics against mocked/stubbed API routes with fake SVG
// preview images), this spec drives the feature against a real asset with
// two genuinely different processed versions, created via the real
// `POST /api/v1/assets/:id/process_image` pipeline — closing the "version
// history diff view" pending E2E gap for the Asset Management module.
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

test.describe('Asset Version History — real diff view E2E', () => {
    test.beforeEach(async ({ page }) => {
        await login(page);
    });

    test('comparing two real versions of a rotated asset renders the diff stage', async ({ page }) => {
        test.setTimeout(60_000);
        await page.goto('/dashboard');
        await page.waitForLoadState('networkidle');
        const csrfToken = await page.evaluate(() => document.querySelector('meta[name="csrf-token"]')?.content);
        const title = `Version Diff E2E ${Date.now()}`;

        // The same 1x1 transparent PNG used throughout this test suite for
        // asset creation — MiniMagick can rotate/process it without error.
        const buffer = Buffer.from(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
            'base64',
        );

        const createRes = await page.request.post('/api/v1/assets', {
            multipart: { file: { name: `version-diff-${Date.now()}.png`, mimeType: 'image/png', buffer }, title },
            headers: { 'X-CSRF-Token': csrfToken },
        });
        expect(createRes.ok()).toBe(true);
        const created = await createRes.json();

        try {
            // Create a second, visually-different version via a real rotate
            // (not a mock) — this is the same processing pipeline the
            // in-browser Image Editor uses ("Save as new version").
            const processRes = await page.request.post(`/api/v1/assets/${created.id}/process_image`, {
                headers: { 'X-CSRF-Token': csrfToken, 'Content-Type': 'application/json' },
                data: { geometry: { rotate: 90 }, save_mode: 'version' },
            });
            expect(processRes.ok()).toBe(true);

            await page.goto(`/assets?id=${created.id}`);
            await page.waitForLoadState('networkidle');

            await page.getByRole('tab', { name: /versions/i }).click();
            await expect(page.getByText(/compare versions/i)).toBeVisible({ timeout: 15_000 });

            // Two real versions exist now (v1 original, v2 rotated) — select
            // both and open the real diff view.
            const checkboxes = page.getByRole('checkbox', { name: /compare v/i });
            await expect(checkboxes).toHaveCount(2);
            await checkboxes.nth(0).click();
            await checkboxes.nth(1).click();

            await page.getByRole('button', { name: /compare selected/i }).click();

            await expect(page.getByText(/comparing v2 against v1/i)).toBeVisible();
            await expect(page.getByLabel(/show diff overlay/i)).toBeVisible();
            await expect(page.getByTestId('version-diff-stage')).toBeVisible();

            // The blend slider and per-version preview labels render with
            // real version numbers (not the placeholder/mocked values).
            await expect(page.getByText(/before \(v1\)/i)).toBeVisible();
            await expect(page.getByText(/after \(v2\)/i)).toBeVisible();
        } finally {
            await page.request.delete(`/api/v1/assets/${created.id}`, { headers: { 'X-CSRF-Token': csrfToken } }).catch(() => {});
            await page.request.delete('/api/v1/bin/bulk_destroy', {
                headers: { 'X-CSRF-Token': csrfToken, 'Content-Type': 'application/json' },
                data: { items: [ { id: created.id, type: 'asset' } ] },
            }).catch(() => {});
        }
    });
});
