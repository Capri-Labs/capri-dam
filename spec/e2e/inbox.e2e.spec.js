const { test, expect } = require('./fixtures');
const { login } = require('./helpers/login');

test.describe('User Inbox', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
  });

  test('inbox is accessible from sidebar', async ({ page }) => {
    await page.goto('/');
    const inboxLink = page.locator('a[href="/inbox"], [data-testid="inbox-nav"]');
    await expect(inboxLink.first()).toBeVisible({ timeout: 5000 });
  });

  test('inbox page renders without errors', async ({ page }) => {
    await page.goto('/inbox');
    await page.waitForLoadState('networkidle');
    await expect(page.locator('body')).not.toContainText('Error');
  });
});

test.describe('Admin Email Engine', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
  });

  test('email templates page loads', async ({ page }) => {
    await page.goto('/admin/email_templates');
    await page.waitForLoadState('networkidle');
    await expect(page.locator('body')).toContainText(/Communication Engine|Email Engine/i);
  });
});
