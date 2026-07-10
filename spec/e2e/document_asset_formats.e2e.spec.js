// E2E coverage for expanded document-format support in the Asset Viewer:
//
//  1. A Word document (.docx) with a LibreOffice-generated flattened preview
//     renders the preview image normally (reuses the same generic
//     `preview_storage_path` mechanism PDF/PSD previews already use).
//  2. An Excel spreadsheet (.xlsx) with NO LibreOffice available shows the
//     "Download Original" fallback instead of a broken preview.
//  3. An Apple Keynote presentation (.key) — which has no rasterisation path
//     at all — also shows the download fallback.
//  4. A plain-text (.txt) document with an extracted `text_preview` renders
//     an inline text preview pane (not a download fallback, not a broken
//     image).
//
// All backend responses are mocked via route interception so this test is
// deterministic and doesn't depend on LibreOffice being installed in the
// test environment.
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

function mockAsset(page, { id, title, contentType, format, documentType, previewUrl, textPreview, extraProps = {} }) {
    return page.route(`**/api/v1/assets/${id}`, async (route) => {
        route.fulfill({
            status: 200,
            contentType: 'application/json',
            body: JSON.stringify({
                id, uuid: id, title, status: 'ready',
                properties: {
                    content_type: contentType, file_size: 500_000, format, document_type: documentType,
                    ...(previewUrl ? { preview_storage_path: 'previews/fake.jpg', preview_content_type: 'image/jpeg' } : {}),
                    ...(textPreview ? { text_preview: textPreview, text_preview_truncated: false, line_count: 3 } : {}),
                    ...extraProps,
                },
                metadata: { content_type: contentType, file_size: 500_000 },
                content_type: contentType,
                size: 500_000,
                folder_id: 'folder-doc-1',
                url: `/api/v1/assets/local/${id}`,
                preview_url: previewUrl || null,
                editable: false,
            }),
        });
    });
}

function mockAssetBinary(page, id, contentType) {
    return page.route(`**/api/v1/assets/local/${id}**`, (route) => {
        route.fulfill({ status: 200, contentType, body: Buffer.from('fake-binary-fixture') });
    });
}

test.describe('AssetViewer — expanded document format support', () => {
    test.beforeEach(async ({ page }) => {
        await login(page);
        await mockEmptyFolderContents(page);
    });

    test('a Word document with a LibreOffice-generated preview renders the flattened preview image', async ({ page }) => {
        await mockAsset(page, {
            id: 'docx-asset-1', title: 'Quarterly-Report.docx',
            contentType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
            format: 'Office Document', documentType: 'Word Document',
            previewUrl: '/api/v1/assets/local/docx-asset-1/preview',
        });
        await mockAssetBinary(page, 'docx-asset-1', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
        await page.route('**/api/v1/assets/local/docx-asset-1/preview**', (route) => {
            route.fulfill({ status: 200, contentType: 'image/jpeg', body: Buffer.from('fake-jpeg-preview') });
        });

        await page.goto('/folders?folder=folder-doc-1&id=docx-asset-1');
        await page.waitForLoadState('networkidle');
        await expect(page.getByRole('banner').getByText('Quarterly-Report.docx')).toBeVisible();

        await expect(page.getByTestId('asset-viewer-preview-image')).toBeVisible();
        await expect(page.getByTestId('asset-preview-download-fallback')).toHaveCount(0);
    });

    test('an Excel spreadsheet with no LibreOffice-generated preview shows the Download Original fallback', async ({ page }) => {
        await mockAsset(page, {
            id: 'xlsx-asset-1', title: 'Budget.xlsx',
            contentType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            format: 'Office Document', documentType: 'Excel Spreadsheet',
            extraProps: { document_conversion_available: false },
        });
        await mockAssetBinary(page, 'xlsx-asset-1', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');

        await page.goto('/folders?folder=folder-doc-1&id=xlsx-asset-1');
        await page.waitForLoadState('networkidle');
        await expect(page.getByRole('banner').getByText('Budget.xlsx')).toBeVisible();

        const fallback = page.getByTestId('asset-preview-download-fallback');
        await expect(fallback).toBeVisible();
        await expect(fallback.getByRole('button', { name: /Download Original/i })).toBeVisible();
    });

    test('an Apple Keynote presentation shows the Download Original fallback (no rasteriser available)', async ({ page }) => {
        await mockAsset(page, {
            id: 'key-asset-1', title: 'Pitch-Deck.key', contentType: 'application/vnd.apple.keynote',
            format: 'Apple iWork Document', documentType: 'Keynote Presentation',
        });
        await mockAssetBinary(page, 'key-asset-1', 'application/vnd.apple.keynote');

        await page.goto('/folders?folder=folder-doc-1&id=key-asset-1');
        await page.waitForLoadState('networkidle');
        await expect(page.getByRole('banner').getByText('Pitch-Deck.key')).toBeVisible();

        const fallback = page.getByTestId('asset-preview-download-fallback');
        await expect(fallback).toBeVisible();
        await expect(fallback.getByRole('button', { name: /Download Original/i })).toBeVisible();
    });

    test('a plain-text document with an extracted preview renders an inline text preview pane', async ({ page }) => {
        await mockAsset(page, {
            id: 'txt-asset-1', title: 'ReadMe.txt', contentType: 'text/plain',
            format: 'Plain Text Document', documentType: 'Plain Text Document',
            textPreview: 'Hello world\nSecond line\nThird line',
        });
        await mockAssetBinary(page, 'txt-asset-1', 'text/plain');

        await page.goto('/folders?folder=folder-doc-1&id=txt-asset-1');
        await page.waitForLoadState('networkidle');
        await expect(page.getByRole('banner').getByText('ReadMe.txt')).toBeVisible();

        const textPreview = page.getByTestId('asset-viewer-text-preview');
        await expect(textPreview).toBeVisible();
        await expect(textPreview).toContainText('Hello world');
        await expect(page.getByTestId('asset-preview-download-fallback')).toHaveCount(0);
    });
});
