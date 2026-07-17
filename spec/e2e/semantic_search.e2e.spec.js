// Real end-to-end E2E test for the "Visual Match" / "Ask AI Agent" semantic
// search pipeline (Api::V1::SearchController#build_semantic_payload).
//
// Prior coverage (spec/e2e/global_search_bar.e2e.spec.js) only exercises the
// mode-dropdown UI mechanics (placeholder swap, suppressed suggestions) — it
// never actually drives a real query through the pgvector nearest-neighbour
// pipeline. This spec closes that "semantic search relevance validation" gap
// by seeding two assets with real, deliberately-orthogonal 1536-dim
// embeddings (via `AssetEmbedding`, the same pgvector-backed model the
// production embedding worker populates) and standing up a tiny local stand-in
// for the AI Gateway (`Api::V1::SearchController#fetch_query_embedding` posts
// to `AI_GATEWAY_URL`/api/embed_query, which defaults to
// http://localhost:8000 and has nothing listening on it in this dev
// environment) so the *real* controller code path — HTTP call out, pgvector
// cosine-similarity ORDER BY, response assembly — runs for real, with only
// the external embedding provider replaced by a deterministic fixture.
//
// Runs against a live Rails server (set E2E_BASE_URL, E2E_EMAIL, E2E_PASSWORD).

const { test, expect } = require('./fixtures');
const { execFileSync } = require('node:child_process');
const http = require('node:http');

const EMAIL    = process.env.E2E_EMAIL    || 'admin@admin.com';
const PASSWORD = process.env.E2E_PASSWORD || 'AdminUser';
const GATEWAY_PORT = 8000;

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

// A 1536-dim vector that is (nearly) all zeros except for one distinguishing
// dimension pushed close to 1 — cosine distance between two such vectors is
// minimal when they share the same "hot" dimension, and large otherwise, so
// this gives fully deterministic nearest-neighbour ordering.
function vectorFor(hotIndex) {
    const v = new Array(1536).fill(0.001);
    v[hotIndex] = 0.98;
    return v;
}

const SUNSET_VECTOR  = vectorFor(10);
const INVOICE_VECTOR = vectorFor(500);

test.describe('Semantic Search — real pgvector relevance E2E', () => {
    test.beforeEach(async ({ page }) => {
        await login(page);
    });

    test('Visual Match mode ranks the embedding-nearest asset first (real pgvector query)', async ({ page }) => {
        test.setTimeout(60_000);

        await page.goto('/dashboard');
        await page.waitForLoadState('networkidle');
        const csrfToken = await page.evaluate(() => document.querySelector('meta[name="csrf-token"]')?.content);
        const stamp = Date.now();
        const sunsetTitle  = `Sunset Beach Photo E2E ${stamp}`;
        const invoiceTitle = `Invoice Document E2E ${stamp}`;

        const buffer = Buffer.from(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
            'base64',
        );

        const createAsset = async (title) => {
            const res = await page.request.post('/api/v1/assets', {
                multipart: { file: { name: `${title.replace(/\s+/g, '-')}.png`, mimeType: 'image/png', buffer }, title },
                headers: { 'X-CSRF-Token': csrfToken },
            });
            expect(res.ok()).toBe(true);
            return res.json();
        };

        const sunsetAsset  = await createAsset(sunsetTitle);
        const invoiceAsset = await createAsset(invoiceTitle);

        // Seed real pgvector AssetEmbedding rows directly (bypassing the
        // async embedding worker, which itself depends on the same
        // unreachable AI Gateway) — mirrors the `execFileSync` DB-seeding
        // pattern already used in spec/e2e/bin.e2e.spec.js for retention-policy
        // backdating.
        const seedScript = `
          sunset = Asset.find_by!(uuid: ${JSON.stringify(sunsetAsset.uuid || sunsetAsset.id)})
          invoice = Asset.find_by!(uuid: ${JSON.stringify(invoiceAsset.uuid || invoiceAsset.id)})
          AssetEmbedding.create!(asset: sunset, embedding: ${JSON.stringify(SUNSET_VECTOR)}, model_name: "e2e-fixture")
          AssetEmbedding.create!(asset: invoice, embedding: ${JSON.stringify(INVOICE_VECTOR)}, model_name: "e2e-fixture")
        `;
        execFileSync('bundle', [ 'exec', 'rails', 'runner', seedScript ], { cwd: process.cwd(), stdio: 'pipe' });

        // Stand in for the AI Gateway: whatever query text is sent, always
        // return the "sunset" vector, so the real pgvector ORDER BY should
        // rank the sunset asset ahead of the (embedding-distant) invoice
        // asset.
        const gateway = http.createServer((req, res) => {
            let body = '';
            req.on('data', (chunk) => { body += chunk; });
            req.on('end', () => {
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ vector: SUNSET_VECTOR }));
            });
        });
        await new Promise((resolve, reject) => {
            gateway.once('error', reject);
            gateway.listen(GATEWAY_PORT, '127.0.0.1', resolve);
        });

        try {
            const searchRes = await page.request.get(
                `/api/v1/search?mode=visual&q=${encodeURIComponent('golden hour sunset over the ocean')}`,
            );
            expect(searchRes.ok()).toBe(true);
            const payload = await searchRes.json();

            // Real semantic pipeline ran (not the ILIKE fallback).
            expect(payload.meta.result_type).toBe('semantic');
            expect(payload.meta.semantic_fallback).toBeFalsy();

            const titles = payload.results.map((r) => r.title);
            expect(titles).toContain(sunsetTitle);
            expect(titles.indexOf(sunsetTitle)).toBeLessThan(
                titles.includes(invoiceTitle) ? titles.indexOf(invoiceTitle) : Infinity,
            );

            // Drive the same query through the real UI (mode dropdown +
            // search bar), not just the raw API, to also confirm the "Visual
            // Match" mode wiring end-to-end.
            await page.goto('/search?mode=visual&q=golden%20hour%20sunset%20over%20the%20ocean');
            await page.waitForLoadState('networkidle');
            await expect(page.getByText(sunsetTitle)).toBeVisible({ timeout: 15_000 });
        } finally {
            await new Promise((resolve) => gateway.close(resolve));
            await page.request.delete(`/api/v1/assets/${sunsetAsset.id}`, { headers: { 'X-CSRF-Token': csrfToken } }).catch(() => {});
            await page.request.delete(`/api/v1/assets/${invoiceAsset.id}`, { headers: { 'X-CSRF-Token': csrfToken } }).catch(() => {});
            await page.request.delete('/api/v1/bin/bulk_destroy', {
                headers: { 'X-CSRF-Token': csrfToken, 'Content-Type': 'application/json' },
                data: { items: [ { id: sunsetAsset.id, type: 'asset' }, { id: invoiceAsset.id, type: 'asset' } ] },
            }).catch(() => {});
        }
    });
});
