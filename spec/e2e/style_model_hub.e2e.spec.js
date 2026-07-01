// @ts-check
const { test, expect } = require('@playwright/test');

const STYLE_HUB_URL = '/ai/models/hub';
const REDIRECT_URL  = '/ai/models';

test.describe('Style & Model Hub — /ai/models/hub', () => {
  test.beforeEach(async ({ page }) => {
    // Log in as admin before each test
    await page.goto('/users/sign_in');
    await page.waitForSelector('input[autocomplete="email"]', { timeout: 15_000 });
    await page.fill('input[autocomplete="email"]', process.env.ADMIN_EMAIL || 'admin@example.com');
    await page.fill('input[autocomplete="current-password"]', process.env.ADMIN_PASSWORD || 'password');
    await page.click('[type="submit"]');
    await page.waitForFunction(
    () => !document.querySelector('input[autocomplete="email"]'),
    { timeout: 15_000 },
  );
    await page.waitForLoadState('networkidle');
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

  test('non-admin is redirected away', async ({ page, context }) => {
    // Clear admin session and sign in as regular user
    await context.clearCookies();
    await page.goto('/users/sign_in');
    await page.waitForSelector('input[autocomplete="email"]', { timeout: 15_000 });
    await page.fill('input[autocomplete="email"]', process.env.MEMBER_EMAIL || 'member@example.com');
    await page.fill('input[autocomplete="current-password"]', process.env.MEMBER_PASSWORD || 'password');
    await page.click('[type="submit"]');
    await page.goto(STYLE_HUB_URL);
    // Expect redirect away from admin screen (dashboard or root)
    await expect(page).not.toHaveURL(new RegExp(STYLE_HUB_URL));
  });

  test('unauthenticated user is redirected to login', async ({ page, context }) => {
    await context.clearCookies();
    await page.goto(STYLE_HUB_URL);
    await expect(page).toHaveURL(/sign_in/);
  });
});

