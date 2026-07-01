'use strict';

// Shared login helper for all E2E tests.
// Handles both the old /dashboard redirect and current / redirect.
const EMAIL = process.env.E2E_EMAIL || 'admin@example.com';
const PASSWORD = process.env.E2E_PASSWORD || 'password123';

async function login(page, email = EMAIL, password = PASSWORD) {
  await page.goto('/users/sign_in');
  await page.fill('input[name="user[email]"]', email);
  await page.fill('input[name="user[password]"]', password);
  await page.click('button[type="submit"]');
  await page.waitForFunction(() => !window.location.href.includes('/users/sign_in'), { timeout: 15_000 });
  await page.waitForLoadState('networkidle');
}

module.exports = { login, EMAIL, PASSWORD };
