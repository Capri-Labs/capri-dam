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
const EMAIL    = process.env.E2E_EMAIL    || 'admin@example.com';
const PASSWORD = process.env.E2E_PASSWORD || 'password123';

async function login(page, email = EMAIL, password = PASSWORD) {
  // Navigate to root — redirects to the React Login SPA when unauthenticated.
  await page.goto('/users/sign_in');
  // Wait for the React login form to mount.
  await page.waitForSelector('input[autocomplete="email"]', { timeout: 15_000 });
  await page.fill('input[autocomplete="email"]', email);
  await page.fill('input[autocomplete="current-password"]', password);
  await page.click('button[type="submit"]');
  // After login React does window.location.href = '/' → authenticated root renders dashboard.
  await page.waitForFunction(
    () => !document.querySelector('input[autocomplete="email"]'),
    { timeout: 15_000 },
  );
  await page.waitForLoadState('networkidle');
}

module.exports = { login, EMAIL, PASSWORD };
