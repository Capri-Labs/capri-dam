// Frontend E2E for the Metadata Tools, driven through a real browser against a
// running server. Produces Istanbul frontend coverage (via fixtures.js) and,
// because requests hit the live Rails app, feeds Coverband backend coverage.
//
// Prereqs: app running at E2E_BASE_URL and a seeded login (set via env).

const { test, expect } = require('./fixtures');

const EMAIL    = process.env.E2E_EMAIL    || 'admin@example.com';
const PASSWORD = process.env.E2E_PASSWORD || 'password123';

async function login(page) {
  await page.goto('/users/sign_in');
  await page.fill('input[name="user[email]"]', EMAIL);
  await page.fill('input[name="user[password]"]', PASSWORD);
  await page.click('button[type="submit"], input[type="submit"]');
  await page.waitForLoadState('networkidle');
}

test.describe('Metadata Tools E2E', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
  });

  test('Metadata Export screen loads and shows the New Export action', async ({ page }) => {
    await page.goto('/tools/metadata_exports');
    await expect(page.getByRole('button', { name: /new export/i })).toBeVisible();
    await expect(page.getByText('Metadata Export')).toBeVisible();
  });

  test('Metadata Import screen loads with the template download link', async ({ page }) => {
    await page.goto('/tools/metadata_imports');
    await expect(page.getByRole('link', { name: /download template/i })).toBeVisible();
    await expect(page.getByRole('button', { name: /new import/i })).toBeVisible();
  });
});

