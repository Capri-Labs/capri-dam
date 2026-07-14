// E2E tests for the System Status → "AI Gateway Controls" tab.
//
// IMPORTANT — current implementation status: AiGatewayTab.jsx is presently a
// UI-only simulation. Its real fetch()/PUT calls to /api/v1/ai_configuration
// are commented out in favour of setTimeout-based fakes (see the component
// source), so "Save & Sync Gateway" always succeeds locally without any
// network round-trip, and reloading the page always resets the form to its
// hardcoded defaults. These tests exercise the actual current behaviour
// (provider/model selection, budget slider, edge-fallback toggle, and the
// simulated save confirmation) rather than asserting a real persisted
// round-trip that doesn't exist yet. Once real persistence is wired up,
// this spec's "Save & Sync Gateway" test should be extended to assert a
// real PUT request/response the same way cdn_image_optimizer_formats.e2e.spec.js
// does for the Storage & Edge tab.
//
// Also note (per product context): AI Gateway controls currently apply
// system-wide only — there is no per-tenant/per-site override yet.
//
// Prereqs: app running at E2E_BASE_URL with seed data (bin/rails db:seed).

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

test.describe('Admin — AI Gateway Controls', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
    await page.goto('/settings/system');
    await page.waitForLoadState('networkidle');
    await page.getByRole('tab', { name: /ai gateway controls/i }).click();
    // The tab renders after a simulated 500ms load delay.
    await expect(page.getByText('AI & LLM Gateway Governance')).toBeVisible({ timeout: 5_000 });
  });

  test('renders the traffic routing, model selection, and budget controls', async ({ page }) => {
    await expect(page.getByRole('combobox', { name: 'Active Cloud Provider' })).toBeVisible();
    await expect(page.getByRole('combobox', { name: /generation model/i })).toBeVisible();
    await expect(page.getByRole('combobox', { name: /embedding model/i })).toBeVisible();
    await expect(page.getByText('Financial Token Governance')).toBeVisible();
    await expect(page.getByText('Hard Limit Trigger (USD)')).toBeVisible();
    await expect(page.getByText('Global System Persona (RAG Base)')).toBeVisible();
  });

  test('"Enable Edge Fallback" defaults on and can be switched off', async ({ page }) => {
    await expect(page.getByText('Enable Edge Fallback')).toBeVisible();
    const toggle = page.locator('input[type="checkbox"]');
    await expect(toggle).toBeChecked();
    await toggle.uncheck({ force: true });
    await expect(toggle).not.toBeChecked();
  });

  test('switching the Active Cloud Provider updates the selected value', async ({ page }) => {
    const provider = page.getByRole('combobox', { name: 'Active Cloud Provider' });
    await provider.click();
    await page.getByRole('option', { name: 'Anthropic (Claude)' }).click();
    await expect(provider).toHaveText(/anthropic/i);
  });

  test('the Generation Model list offers Claude 3.5 Sonnet and Llama 3 70B alongside the OpenAI defaults', async ({ page }) => {
    await page.getByRole('combobox', { name: /generation model/i }).click();
    await expect(page.getByRole('option', { name: /gpt-4o \(high intelligence\)/i })).toBeVisible();
    await expect(page.getByRole('option', { name: /claude 3\.5 sonnet/i })).toBeVisible();
    await expect(page.getByRole('option', { name: /llama 3 70b/i })).toBeVisible();
    await page.keyboard.press('Escape');
  });

  test('entering a system prompt and clicking "Save & Sync Gateway" shows the sync confirmation', async ({ page }) => {
    await page.getByPlaceholder(/you are an enterprise ai working within a capri dam/i).fill('You are an enterprise AI working within a Capri DAM instance.');
    await page.getByRole('button', { name: /save & sync gateway/i }).click();
    await expect(page.getByText(/ai gateway routing updated/i)).toBeVisible({ timeout: 5_000 });
  });

  test('the Circuit Breaker "Kill Switch" control is visible and enabled', async ({ page }) => {
    const killSwitch = page.getByRole('button', { name: /kill switch/i });
    await expect(killSwitch).toBeVisible();
    await expect(killSwitch).toBeEnabled();
  });
});
