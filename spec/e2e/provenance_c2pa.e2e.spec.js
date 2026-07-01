// E2E tests for the Provenance & C2PA screen (/ai/governance/provenance).
// Requires the Rails app running at E2E_BASE_URL, seeded with an admin account.
//
// Prereqs: app running at E2E_BASE_URL and a seeded login (set via env).

const { test, expect } = require('./fixtures');

const EMAIL    = process.env.E2E_EMAIL    || 'admin@example.com';
const PASSWORD = process.env.E2E_PASSWORD || 'password123';

async function login(page) {
  await page.goto('/users/sign_in');
  await page.waitForSelector('input[autocomplete="email"]', { timeout: 15_000 });
  await page.fill('input[autocomplete="email"]', EMAIL);
  await page.fill('input[autocomplete="current-password"]', PASSWORD);
  await page.click('button[type="submit"], input[type="submit"]');
  await page.waitForLoadState('networkidle');
}

test.describe('Provenance & C2PA screen', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
  });

  test('page loads at canonical URL with correct title', async ({ page }) => {
    await page.goto('/ai/governance/provenance');
    await expect(page).toHaveTitle(/Capri/);
    await expect(page.getByText(/Provenance/i)).toBeVisible();
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
    await expect(page.getByText(/Provenance Records/i)).toBeVisible();
    await expect(page.getByText(/Policy Settings/i)).toBeVisible();
    await expect(page.getByText(/Batch Actions/i)).toBeVisible();
  });

  test('Policy Settings tab shows the save button', async ({ page }) => {
    await page.goto('/ai/governance/provenance');
    await page.getByText(/Policy Settings/i).click();
    await expect(page.getByRole('button', { name: /save policy/i })).toBeVisible();
  });

  test('Batch Actions tab shows the launch button', async ({ page }) => {
    await page.goto('/ai/governance/provenance');
    await page.getByText(/Batch Actions/i).click();
    await expect(page.getByRole('button', { name: /launch batch task/i })).toBeVisible();
  });

  test('non-admin is redirected away from the provenance screen', async ({ page }) => {
    // Sign out first
    await page.goto('/users/sign_out');
    // Sign in as a regular user
    const regularEmail    = process.env.E2E_USER_EMAIL    || 'user@example.com';
    const regularPassword = process.env.E2E_USER_PASSWORD || 'password123';
    await page.goto('/users/sign_in');
    await page.waitForSelector('input[autocomplete="email"]', { timeout: 15_000 });
    await page.fill('input[autocomplete="email"]', regularEmail);
    await page.fill('input[autocomplete="current-password"]', regularPassword);
    await page.click('button[type="submit"], input[type="submit"]');
    await page.waitForLoadState('networkidle');

    await page.goto('/ai/governance/provenance');
    // Should be redirected — not on the provenance page
    await expect(page).not.toHaveURL(/\/ai\/governance\/provenance/);
  });

  test('unauthenticated user is redirected to sign-in', async ({ page }) => {
    // Clear session by going to sign-out
    await page.goto('/users/sign_out');
    await page.goto('/ai/governance/provenance');
    await expect(page).toHaveURL(/sign_in/);
  });
});

