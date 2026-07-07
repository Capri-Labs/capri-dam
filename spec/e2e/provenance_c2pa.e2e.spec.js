// E2E tests for the Provenance & C2PA screen (/ai/governance/provenance).
// Requires the Rails app running at E2E_BASE_URL, seeded with an admin account.
//
// Prereqs: app running at E2E_BASE_URL and a seeded login (set via env).

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

  // The app performs a full-page redirect (window.location.href = '/') after
  // a successful AJAX sign-in; wait for it and then double-check the session
  // actually took effect (guards against a rare Set-Cookie/navigation race).
  await page.waitForURL(/^https?:\/\/[^/]+\/?(\?.*)?$/, { timeout: 15_000 });
  await page.waitForLoadState('networkidle');

  const signedIn = await page.locator('#header-root').getAttribute('data-signed-in');
  if (signedIn !== 'true') {
    await page.reload();
    await page.waitForLoadState('networkidle');
  }
}

async function signOut(page) {
  // Devise's sign_out route only accepts DELETE (config.sign_out_via = :delete),
  // so a plain page.goto('/users/sign_out') (GET) never actually logs the user
  // out — it 404s/405s silently and the session cookie remains valid. Issue a
  // real DELETE request (with CSRF token) from inside the page context instead.
  await page.evaluate(async () => {
    const token = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content');
    await fetch('/users/sign_out', {
      method: 'DELETE',
      headers: {
        ...(token ? { 'X-CSRF-Token': token } : {}),
        'Content-Type': 'application/json',
      },
    });
  });
}

test.describe('Provenance & C2PA screen', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
  });

  test('page loads at canonical URL with correct title', async ({ page }) => {
    await page.goto('/ai/governance/provenance');
    await expect(page).toHaveTitle(/Capri/);
    await expect(page.getByRole('heading', { name: 'Provenance & C2PA' })).toBeVisible();
  });

  test('/ai/governance redirects to /ai/governance/provenance', async ({ page }) => {
    await page.goto('/ai/governance');
    await expect(page).toHaveURL(/\/ai\/governance\/provenance/);
  });

  test('stat cards are rendered', async ({ page }) => {
    await page.goto('/ai/governance/provenance');
    // At least one of the known stat card labels appears
    await expect(page.getByText(/Verified|No Manifest|DAM-Signed/i).first()).toBeVisible();
  });

  test('three tabs are visible: Provenance Records, Policy Settings, Batch Actions', async ({ page }) => {
    await page.goto('/ai/governance/provenance');
    await expect(page.getByRole('button', { name: /^Provenance Records$/i })).toBeVisible();
    await expect(page.getByRole('button', { name: /^Policy Settings$/i })).toBeVisible();
    await expect(page.getByRole('button', { name: /^Batch Actions$/i })).toBeVisible();
  });

  test('Policy Settings tab shows the save button', async ({ page }) => {
    await page.goto('/ai/governance/provenance');
    await page.getByRole('button', { name: /^Policy Settings$/i }).click();
    await expect(page.getByRole('button', { name: /save policy/i })).toBeVisible();
  });

  test('Batch Actions tab shows the launch button', async ({ page }) => {
    await page.goto('/ai/governance/provenance');
    await page.getByRole('button', { name: /^Batch Actions$/i }).click();
    await expect(page.getByRole('button', { name: /launch batch task/i })).toBeVisible();
  });

  test('non-admin is forbidden from the provenance screen', async ({ page }) => {
    // Sign out first
    await signOut(page);
    // Sign in as a regular user
    const regularEmail    = process.env.E2E_USER_EMAIL    || 'user@example.com';
    const regularPassword = process.env.E2E_USER_PASSWORD || 'Password123!';
    await page.goto('/users/sign_in');
    await page.waitForSelector('input[autocomplete="email"]', { timeout: 15_000 });
    await page.fill('input[autocomplete="email"]', regularEmail);
    await page.fill('input[autocomplete="current-password"]', regularPassword);

    // Wait for the login AJAX call and subsequent full-page redirect to
    // settle before navigating to the protected page — otherwise the
    // session cookie may not be committed yet, racing with the goto() below.
    const [response] = await Promise.all([
      page.waitForResponse((res) => res.url().includes('/users/sign_in.json'), { timeout: 15_000 }),
      page.click('button[type="submit"], input[type="submit"]'),
    ]);
    if (!response.ok()) throw new Error(`login failed with status ${response.status()}`);
    await page.waitForURL(/^https?:\/\/[^/]+\/?(\?.*)?$/, { timeout: 15_000 });
    await page.waitForLoadState('networkidle');

    // Ai::UiController#require_admin! renders a 403 JSON body for admin-only
    // shells regardless of request format (see spec/requests/ai_ui_spec.rb) —
    // the browser stays on the same URL, it just gets a forbidden response
    // instead of the page markup.
    const provenanceResponse = await page.goto('/ai/governance/provenance');
    expect(provenanceResponse.status()).toBe(403);
    expect(await provenanceResponse.json()).toEqual({ error: 'Administrator privileges required.' });
  });

  test('unauthenticated user is redirected to sign-in', async ({ page }) => {
    // Clear session by signing out
    await signOut(page);
    await page.goto('/ai/governance/provenance');
    // The app's Sessions#new redirects to root ("/"), where the unauthenticated
    // React shell renders the Login SPA — see auth.e2e.spec.js for the same pattern.
    await expect(page).toHaveURL(/\/$/);
  });
});

