// @ts-check
const { test, expect } = require('@playwright/test');

const STYLE_HUB_URL = '/ai/models/hub';
const REDIRECT_URL  = '/ai/models';

test.describe('Style & Model Hub — /ai/models/hub', () => {
  test.beforeEach(async ({ page }) => {
    // Log in as admin before each test
    await page.goto('/users/sign_in');
    await page.waitForSelector('input[autocomplete="email"]', { timeout: 15_000 });
    await page.fill('input[autocomplete="email"]', process.env.ADMIN_EMAIL || 'admin@admin.com');
    await page.fill('input[autocomplete="current-password"]', process.env.ADMIN_PASSWORD || 'AdminUser');

    const [response] = await Promise.all([
      page.waitForResponse((res) => res.url().includes('/users/sign_in.json'), { timeout: 15_000 }),
      page.click('[type="submit"]'),
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
  });

  test('page loads at canonical URL', async ({ page }) => {
    await page.goto(STYLE_HUB_URL);
    await expect(page).toHaveURL(new RegExp(STYLE_HUB_URL));
    await expect(page.locator('h4')).toContainText('Style & Model Hub');
  });

  test('/ai/models redirects to /ai/models/hub', async ({ page }) => {
    await page.goto(REDIRECT_URL);
    await expect(page).toHaveURL(new RegExp(STYLE_HUB_URL));
  });

  test('three tabs are visible', async ({ page }) => {
    await page.goto(STYLE_HUB_URL);
    await expect(page.getByRole('tab', { name: /models/i })).toBeVisible();
    await expect(page.getByRole('tab', { name: /style presets/i })).toBeVisible();
    await expect(page.getByRole('tab', { name: /batch tasks/i })).toBeVisible();
  });

  test('Models tab shows table with add model button', async ({ page }) => {
    await page.goto(STYLE_HUB_URL);
    await expect(page.getByText('Registered AI Models')).toBeVisible();
    await expect(page.getByRole('button', { name: /add model/i })).toBeVisible();
  });

  test('Style Presets tab shows preset grid', async ({ page }) => {
    await page.goto(STYLE_HUB_URL);
    await page.getByRole('tab', { name: /style presets/i }).click();
    await expect(page.getByRole('button', { name: /new preset/i })).toBeVisible();
  });

  test('Batch Tasks tab shows launch button', async ({ page }) => {
    await page.goto(STYLE_HUB_URL);
    await page.getByRole('tab', { name: /batch tasks/i }).click();
    await expect(page.getByRole('button', { name: /launch task/i })).toBeVisible();
  });

  test('non-admin is forbidden from the admin-only hub', async ({ page, context }) => {
    // Clear admin session and sign in as regular user
    await context.clearCookies();
    await page.goto('/users/sign_in');
    await page.waitForSelector('input[autocomplete="email"]', { timeout: 15_000 });
    await page.fill('input[autocomplete="email"]', process.env.MEMBER_EMAIL || 'member@example.com');
    await page.fill('input[autocomplete="current-password"]', process.env.MEMBER_PASSWORD || 'password');

    // Wait for the login AJAX call and the subsequent full-page redirect to
    // settle before navigating away — otherwise the session cookie may not
    // be committed yet, racing with the goto() below.
    const [response] = await Promise.all([
      page.waitForResponse((res) => res.url().includes('/users/sign_in.json'), { timeout: 15_000 }),
      page.click('[type="submit"]'),
    ]);
    if (!response.ok()) throw new Error(`login failed with status ${response.status()}`);
    await page.waitForURL(/^https?:\/\/[^/]+\/?(\?.*)?$/, { timeout: 15_000 });
    await page.waitForLoadState('networkidle');

    // Ai::UiController#require_admin! renders a 403 JSON body for admin-only
    // shells regardless of request format (see spec/requests/ai_ui_spec.rb) —
    // the browser stays on the same URL, it just gets a forbidden response
    // instead of the page markup.
    const hubResponse = await page.goto(STYLE_HUB_URL);
    expect(hubResponse.status()).toBe(403);
    expect(await hubResponse.json()).toEqual({ error: 'Administrator privileges required.' });
  });

  test('unauthenticated user is redirected to login', async ({ page, context }) => {
    await context.clearCookies();
    await page.goto(STYLE_HUB_URL);
    // The app's Sessions#new redirects to root ("/"), where the unauthenticated
    // React shell renders the Login SPA — see auth.e2e.spec.js for the same pattern.
    await expect(page).toHaveURL(/\/$/);
  });
});

