// E2E coverage for the Upload & Enrich overlay fixes:
//
//  1. Manual tags typed into the sidebar's Tags Autocomplete AND per-file AI
//     tags (from the per-card "AI enhance" action) are BOTH sent as the
//     `tags` metadata field on `POST /api/v1/assets`, de-duplicated —
//     previously `handleUploadAll` only sent the sidebar's manual tags and
//     silently dropped any per-file AI tags. See UploadWorkspace.jsx's
//     `handleUploadAll` (`combinedTags`).
//  2. The upload-time Duplicate Overlay (`LegacyDuplicateResolverDialog`)
//     flags a matched existing asset that lives in the Recycle Bin with a
//     "Bin" chip, matching the Search results page's BinChip pattern — this
//     relies on `check_hashes` returning `in_bin` per duplicate match (see
//     Api::V1::AssetsController#check_hashes).
//
// All backend responses are mocked via route interception so these tests
// are deterministic and don't depend on live seed data.
//
// Runs against a live Rails server (set E2E_BASE_URL, E2E_EMAIL, E2E_PASSWORD).

const { test, expect } = require('./fixtures');

// 1x1 transparent PNG, used as an in-memory upload fixture (no file on disk
// needed — Playwright's setInputFiles accepts a { name, mimeType, buffer }).
const SAMPLE_PNG_BUFFER = Buffer.from(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    'base64'
);

const EMAIL    = process.env.E2E_EMAIL    || 'admin@admin.com';
const PASSWORD = process.env.E2E_PASSWORD || 'AdminUser';

async function login(page) {
    await page.goto('/');
    const emailInput = page.locator('input[autocomplete="email"]');
    const loginFormVisible = await emailInput.isVisible({ timeout: 5_000 }).catch(() => false);

    if (!loginFormVisible) {
        await page.waitForLoadState('networkidle');
        const signedIn = await page.locator('#header-root').getAttribute('data-signed-in').catch(() => null);
        if (signedIn === 'true') return;
        await page.goto('/users/sign_in');
        const directLoginVisible = await emailInput.isVisible({ timeout: 5_000 }).catch(() => false);
        if (!directLoginVisible) {
            const signedInRetry = await page.locator('#header-root').getAttribute('data-signed-in').catch(() => null);
            if (signedInRetry === 'true') return;
            throw new Error('Login form did not render and no signed-in session was detected.');
        }
    }

    await emailInput.fill(EMAIL);
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

function mockEmptyFolderContents(page) {
    return page.route('**/api/v1/folders/**', (route) => {
        route.fulfill({
            status: 200,
            contentType: 'application/json',
            body: JSON.stringify({
                folders: [],
                assets: [],
                breadcrumbs: [ { id: 'root', name: 'Home' } ],
                sort: { field: 'created_at', direction: 'desc' },
            }),
        });
    });
}

function mockUploadWorkspaceBootstrap(page) {
    return Promise.all([
        page.route('**/api/v1/metadata_schemas', (route) => {
            route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify([]) });
        }),
        page.route('**/api/v1/upload_restrictions', (route) => {
            route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ allowed_mime_types: [] }) });
        }),
    ]);
}

async function openUploadOverlay(page) {
    await mockEmptyFolderContents(page);
    await mockUploadWorkspaceBootstrap(page);
    await page.goto('/folders');
    await page.waitForLoadState('networkidle');
    await page.getByRole('button', { name: /upload asset/i }).click();
    await expect(page.getByText('Upload & Enrich')).toBeVisible();
}

async function dropFixtureFile(page) {
    const fileInput = page.locator('input[type="file"]');
    await fileInput.setInputFiles({ name: 'sample.png', mimeType: 'image/png', buffer: SAMPLE_PNG_BUFFER });
}

test.describe('Upload overlay — manual + AI tag merging', () => {
    test.beforeEach(async ({ page }) => { await login(page); });

    test('merges sidebar manual tags with the per-file AI tags into the uploaded asset metadata', async ({ page }) => {
        await openUploadOverlay(page);

        await page.route('**/api/v1/assets/check_hashes', (route) => {
            route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ duplicates: {} }) });
        });

        await dropFixtureFile(page);
        // The staged file's filename renders as the value of a read-only textbox in the card.
        await expect(page.locator('input[value="sample.png"]').first()).toBeVisible({ timeout: 15_000 });

        // Type a manual tag into the sidebar's Tags Autocomplete.
        const tagsInput = page.getByTestId('upload-manual-tags').locator('input');
        await tagsInput.fill('Campaign');
        await tagsInput.press('Enter');
        await expect(page.getByText('Campaign', { exact: true })).toBeVisible();

        // Trigger the per-file AI enhance action (adds 'Enhanced' + 'Web-Ready').
        await page.getByRole('button', { name: /run ai enhance on this file/i }).click();
        await expect(page.getByText('Enhanced', { exact: true })).toBeVisible();

        let uploadedTags = null;
        await page.route('**/api/v1/assets', async (route) => {
            if (route.request().method() !== 'POST') return route.continue();
            const body = route.request().postData() || '';
            const match = body.match(/name="metadata"\r?\n\r?\n([^\r\n]+)/);
            if (match) {
                try { uploadedTags = JSON.parse(match[1]).tags; } catch (_) { /* ignore */ }
            }
            route.fulfill({
                status: 201,
                contentType: 'application/json',
                body: JSON.stringify({ id: 'new-asset-1', uuid: 'new-asset-1', title: 'sample.png' }),
            });
        });

        await page.getByRole('button', { name: /upload \(1\)/i }).click();
        await expect.poll(() => uploadedTags).not.toBeNull();

        expect(uploadedTags).toEqual(expect.arrayContaining(['Campaign', 'Enhanced', 'Web-Ready']));
        expect(uploadedTags).toHaveLength(3);
    });
});

test.describe('Upload overlay — Duplicate Overlay Bin chip', () => {
    test.beforeEach(async ({ page }) => { await login(page); });

    test('flags a matched duplicate that lives in the Recycle Bin with a Bin chip', async ({ page }) => {
        await openUploadOverlay(page);

        // `in_bin` is computed backend-side as
        // `asset.deleted_at.present? || asset.folder&.deleted_at.present?` —
        // true whether the asset itself was soft-deleted, or only its
        // containing folder was (see spec/requests/api/v1/assets_request_spec.rb
        // for the two corresponding backend regression tests). The frontend
        // only needs to react to the resulting boolean flag, so a single
        // `in_bin: true` mock covers both backend cases here.
        await page.route('**/api/v1/assets/check_hashes', (route) => {
            const body = route.request().postDataJSON();
            const hash = (body && body.hashes && body.hashes[0]) || 'hash-1';
            const duplicates = {};
            duplicates[hash] = [
                {
                    id: 'existing-1', title: 'Existing Binned Asset.png',
                    url: '/api/v1/assets/local/existing-1',
                    folder_name: 'Marketing', folder_id: 'folder-9',
                    in_bin: true,
                },
            ];
            route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ duplicates }) });
        });

        await dropFixtureFile(page);

        await page.getByText(/duplicate found/i).click();
        await expect(page.getByRole('heading', { name: /resolve duplicate/i })).toBeVisible();
        // The BinChip renders the localized "Bin" badge — once as an overlay on
        // the primary preview image, once next to the binned location chip.
        await expect(page.getByText('Bin', { exact: true }).first()).toBeVisible({ timeout: 10_000 });
        expect(await page.getByText('Bin', { exact: true }).count()).toBeGreaterThanOrEqual(2);
    });
});

test.describe('Upload overlay — progress indicators', () => {
    test.beforeEach(async ({ page }) => { await login(page); });

    test('shows batch and per-file upload progress while a staged upload is in flight', async ({ page }) => {
        await openUploadOverlay(page);

        await page.route('**/api/v1/assets/check_hashes', (route) => {
            route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ duplicates: {} }) });
        });

        await dropFixtureFile(page);
        await expect(page.locator('input[value="sample.png"]').first()).toBeVisible({ timeout: 15_000 });

        let uploadStarted = false;
        let uploadFinished = false;
        await page.route('**/api/v1/assets', async (route) => {
            if (route.request().method() !== 'POST') return route.continue();
            uploadStarted = true;
            await new Promise((resolve) => setTimeout(resolve, 1200));
            uploadFinished = true;
            await route.fulfill({
                status: 201,
                contentType: 'application/json',
                body: JSON.stringify({ id: 'progress-asset-1', uuid: 'progress-asset-1', title: 'sample.png' }),
            });
        });

        await page.getByRole('button', { name: /upload \(1\)/i }).click();
        await expect.poll(() => uploadStarted).toBe(true);

        await expect(page.getByTestId('upload-progress')).toBeVisible();
        await expect(page.getByTestId('upload-progress')).toContainText(/uploading/i);
        await expect(page.getByTestId('upload-progress')).toContainText(/0 of 1/i);
        await expect(page.getByText(/uploading\.\.\./i)).toBeVisible();

        await expect.poll(() => uploadFinished).toBe(true);
        await expect(page.getByText('Upload & Enrich')).toHaveCount(0, { timeout: 10_000 });
    });
});
