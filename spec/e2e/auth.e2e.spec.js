'use strict';

const { test, expect } = require('./fixtures');
const { login, EMAIL } = require('./helpers/login');

const INVALID_PASSWORD = process.env.E2E_INVALID_PASSWORD || 'wrong-password';
const SSO_PATH = process.env.E2E_SSO_PATH || '/users/auth/keycloak_openid';

async function signOut(page) {
  const csrfToken = await page.locator('meta[name="csrf-token"]').getAttribute('content');
  await page.evaluate(async ({ token }) => {
    await fetch('/users/sign_out', {
      method: 'DELETE',
      headers: {
        'X-CSRF-Token': token,
        'Content-Type': 'application/json'
      }
    });
  }, { token: csrfToken });
}

test.describe('Authentication flows', () => {
  // Sessions#new redirects /users/sign_in → / so the final URL is root (/)
  // which renders the React Login SPA when unauthenticated.
  test('redirects unauthenticated users from /dashboard to the login page', async ({ page }) => {
    await page.goto('/dashboard');
    // After the redirect chain /dashboard → /users/sign_in → /, the React Login form is shown.
    await expect(page).toHaveURL(/\/$/);
    await expect(page.locator('#root')).toHaveAttribute('data-view', 'login');
  });

  test('shows an error on invalid credentials', async ({ page }) => {
    await page.goto('/users/sign_in');
    await page.waitForSelector('input[autocomplete="email"]', { timeout: 15_000 });
    await page.fill('input[autocomplete="email"]', EMAIL);
    await page.fill('input[autocomplete="current-password"]', INVALID_PASSWORD);
    await page.click('button[type="submit"]');

    await expect(page.getByText(/Invalid email or password/i)).toBeVisible();
    // Error is shown on the same login page (/)
    await expect(page.locator('#root')).toHaveAttribute('data-view', 'login');
  });

  test('redirects GET /users/sign_up to root when registration is disabled', async ({ page }) => {
    await page.goto('/users/sign_up');

    await expect(page).toHaveURL(/\/$/);
    await expect(page.locator('#root')).toHaveAttribute('data-view', 'login');
  });

  test('redirects successful login to root instead of /dashboard', async ({ page }) => {
    await login(page);

    await expect(page).toHaveURL(/\/$/);
    await expect(page.locator('#root')).toHaveAttribute('data-view', 'dashboard');
  });

  test('redirects authenticated users away from /users/sign_in to root', async ({ page }) => {
    await login(page);
    await page.goto('/users/sign_in');
    await page.waitForURL('**/');
    await page.waitForLoadState('networkidle');

    await expect(page).toHaveURL(/\/$/);
    await expect(page.locator('#root')).toHaveAttribute('data-view', 'dashboard');
  });

  test('sign out returns the browser to the login page for protected routes', async ({ page }) => {
    await login(page);
    await signOut(page);
    await page.goto('/dashboard');

    // After sign-out the redirect chain ends at / (login page)
    await expect(page).toHaveURL(/\/$/);
    await expect(page.locator('#root')).toHaveAttribute('data-view', 'login');
  });

  test('SSO button posts to the configured Keycloak path', async ({ page }) => {
    await page.goto('/users/sign_in');
    await page.waitForSelector('input[autocomplete="email"]', { timeout: 15_000 });

    const [request] = await Promise.all([
      page.waitForRequest((candidate) => (
        candidate.url().endsWith(SSO_PATH) && candidate.method() === 'POST'
      )),
      page.getByRole('button', { name: /Sign in with Enterprise SSO/i }).click()
    ]);

    expect(new URL(request.url()).pathname).toBe(SSO_PATH);
  });
});
