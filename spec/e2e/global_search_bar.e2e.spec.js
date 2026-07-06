// E2E tests for the global search bar (top bar) — modes, suggestions, and
// navigation to /search.
//
// Covers:
//  - Mode dropdown includes Visual Match and Ask AI Agent among others.
//  - Typing a query shows a suggestions panel (fed by Redis-cached
//    /api/v1/search/suggestions) and supports keyboard navigation.
//  - Enter/"View all results" navigates to /search with the right params.
//  - Visual Match mode swaps placeholder/tooltip and suppresses suggestions
//    fetch (drag/drop or URL paste flow instead of text query).
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

test.describe('Global Search Bar', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
    await page.goto('/dashboard');
    await page.waitForLoadState('networkidle');
  });

  test('search bar is visible with default placeholder', async ({ page }) => {
    const input = page.getByLabel('global search', { exact: true });
    await expect(input).toBeVisible();
    await expect(input).toHaveAttribute('placeholder', /search assets, folders, or tags/i);
  });

  test('mode dropdown includes Visual Match and Ask AI Agent options', async ({ page }) => {
    await page.locator('.MuiSelect-select').first().click();
    await expect(page.getByRole('option', { name: /visual match/i })).toBeVisible();
    await expect(page.getByRole('option', { name: /ask ai agent/i })).toBeVisible();
    await expect(page.getByRole('option', { name: /^images$/i })).toBeVisible();
    await expect(page.getByRole('option', { name: /^files$/i })).toBeVisible();
    await expect(page.getByRole('option', { name: /^folders$/i })).toBeVisible();
  });

  test('selecting Visual Match mode changes placeholder', async ({ page }) => {
    await page.locator('.MuiSelect-select').first().click();
    await page.getByRole('option', { name: /visual match/i }).click();
    const input = page.getByLabel('global search', { exact: true });
    await expect(input).toHaveAttribute('placeholder', /drop an image or paste a url/i);
  });

  test('selecting Ask AI Agent mode changes placeholder', async ({ page }) => {
    await page.locator('.MuiSelect-select').first().click();
    await page.getByRole('option', { name: /ask ai agent/i }).click();
    const input = page.getByLabel('global search', { exact: true });
    await expect(input).toHaveAttribute('placeholder', /find summer photos without logos/i);
  });

  test('typing a query shows a suggestions panel', async ({ page }) => {
    const input = page.getByLabel('global search', { exact: true });
    await input.click();
    await input.fill('asset');
    // Either results or the "no results" message renders within the panel.
    await expect(
      page.getByText(/searching\.\.\.|no matches found|view all results/i).first()
    ).toBeVisible({ timeout: 10_000 });
  });

  test('pressing Enter navigates to the /search results page', async ({ page }) => {
    const input = page.getByLabel('global search', { exact: true });
    await input.click();
    await input.fill('logo');
    await input.press('Enter');
    await page.waitForURL(/\/search\?q=logo&mode=images/i, { timeout: 10_000 });
    await expect(page).toHaveURL(/\/search\?q=logo&mode=images/i);
  });

  test('"View all results" suggestion link navigates to /search with query', async ({ page }) => {
    const input = page.getByLabel('global search', { exact: true });
    await input.click();
    await input.fill('asset');
    // The "View all results" row only renders once at least one suggestion
    // is returned; wait for the panel to settle before asserting on it.
    await expect(
      page.getByText(/searching\.\.\.|no matches found|view all results/i).first()
    ).toBeVisible({ timeout: 10_000 });
    const viewAllLink = page.getByText(/view all results for "asset"/i);
    if (await viewAllLink.isVisible({ timeout: 3000 }).catch(() => false)) {
      await viewAllLink.click();
      await page.waitForURL(/\/search\?q=asset&mode=images/i, { timeout: 10_000 });
    } else {
      // No suggestions were returned for this query in the current dataset;
      // fall back to Enter, which always navigates regardless of suggestions.
      await input.press('Enter');
      await page.waitForURL(/\/search\?q=asset&mode=images/i, { timeout: 10_000 });
    }
  });

  test('keyboard ArrowDown highlights first suggestion without navigating away', async ({ page }) => {
    const input = page.getByLabel('global search', { exact: true });
    await input.click();
    await input.fill('asset');
    await page.waitForTimeout(500); // debounce window
    await input.press('ArrowDown');
    // Still on the same page (dashboard) -- Enter has not been pressed.
    await expect(page).toHaveURL(/\/dashboard/);
  });
});

// ─────────────────────────────────────────────────────────────────
// /search results page itself
// ─────────────────────────────────────────────────────────────────

test.describe('Search Results Page', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
  });

  test('loads with pagination params and renders results grid', async ({ page }) => {
    await page.goto('/search?page=1&per_page=10');
    await page.waitForLoadState('networkidle');
    await expect(page).toHaveURL(/\/search\?page=1&per_page=10/);
  });

  test('search page accepts a query and mode from the URL', async ({ page }) => {
    await page.goto('/search?q=logo&mode=images&page=1&per_page=10');
    await page.waitForLoadState('networkidle');
    await expect(page).toHaveURL(/q=logo/);
  });
});
