'use strict';

// Shared login helper for all E2E tests.
//
// The app uses a React SPA login form (not a Devise HTML form).
// The Rails Sessions#new action redirects to "/" which renders the
// React Login component when the user is unauthenticated.
//
// Correct selectors:
//   email    → input[autocomplete="email"]
//   password → input[autocomplete="current-password"]
//   submit   → button[type="submit"]
const EMAIL    = process.env.E2E_EMAIL    || 'admin@admin.com';
const PASSWORD = process.env.E2E_PASSWORD || 'AdminUser';

async function login(page, email = EMAIL, password = PASSWORD) {
  // Navigate to root — redirects to the React Login SPA when unauthenticated.
  await page.goto('/users/sign_in');
  // Wait for the React login form to mount.
  await page.waitForSelector('input[autocomplete="email"]', { timeout: 15_000 });
  await page.fill('input[autocomplete="email"]', email);
  await page.fill('input[autocomplete="current-password"]', password);

  const [response] = await Promise.all([
    page.waitForResponse((res) => res.url().includes('/users/sign_in.json'), { timeout: 15_000 }),
    page.click('button[type="submit"]'),
  ]);
  if (!response.ok()) throw new Error(`login failed with status ${response.status()}`);

  // After login React does window.location.href = '/' → authenticated root
  // renders the dashboard. Wait for that redirect, then double-check the
  // session actually took effect (guards against a rare Set-Cookie/navigation
  // race that otherwise leaves the page looking signed-out).
  await page.waitForURL(/^https?:\/\/[^/]+\/?(\?.*)?$/, { timeout: 15_000 });
  await page.waitForLoadState('networkidle');

  const signedIn = await page.locator('#header-root').getAttribute('data-signed-in');
  if (signedIn !== 'true') {
    await page.reload();
    await page.waitForLoadState('networkidle');
  }
}

module.exports = { login, EMAIL, PASSWORD };
