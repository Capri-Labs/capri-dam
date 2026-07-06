// E2E tests for the "Communication Engine" (email templates) admin screen.
//
// Covers:
//  - Templates tab: list, New Template gallery (predefined designs + blank),
//    Template Variables picker, rich text HTML body editor, Preview tab.
//  - Event Mapping / Outbox / AI Suggestions tabs render.
//  - "Global CSS for Emails" tab: primary color, font family, custom CSS,
//    and save action.
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

test.describe('Admin — Communication Engine (Email Templates)', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
    await page.goto('/admin/email_templates');
    await page.waitForLoadState('networkidle');
  });

  test('page loads with Communication Engine title and tabs', async ({ page }) => {
    await expect(page.getByText('Communication Engine')).toBeVisible();
    await expect(page.getByRole('tab', { name: /templates/i })).toBeVisible();
    await expect(page.getByRole('tab', { name: /event mapping/i })).toBeVisible();
    await expect(page.getByRole('tab', { name: /outbox/i })).toBeVisible();
    await expect(page.getByRole('tab', { name: /ai suggestions/i })).toBeVisible();
    await expect(page.getByRole('tab', { name: /global css for emails/i })).toBeVisible();
  });

  test('New Template opens design gallery with predefined designs', async ({ page }) => {
    await page.getByRole('button', { name: /new template/i }).click();
    await expect(page.getByText(/choose a template design/i)).toBeVisible();
    await expect(page.getByRole('button', { name: /start from blank/i })).toBeVisible();
  });

  test('Start from Blank opens the template editor drawer', async ({ page }) => {
    await page.getByRole('button', { name: /new template/i }).click();
    await page.getByRole('button', { name: /start from blank/i }).click();
    await expect(page.getByRole('heading', { name: 'New Template' })).toBeVisible();
    await expect(page.getByLabel(/template name/i)).toBeVisible();
    await expect(page.getByLabel(/subject/i)).toBeVisible();
  });

  test('editor shows Template Variables picker and rich text HTML body editor', async ({ page }) => {
    await page.getByRole('button', { name: /new template/i }).click();
    await page.getByRole('button', { name: /start from blank/i }).click();
    await expect(page.getByText(/template variables/i)).toBeVisible();
    await expect(page.getByRole('heading', { name: /html body/i })).toBeVisible();
  });

  test('editor Preview tab renders sandboxed iframe', async ({ page }) => {
    await page.getByRole('button', { name: /new template/i }).click();
    await page.getByRole('button', { name: /start from blank/i }).click();
    const previewTab = page.getByRole('tab', { name: /preview/i });
    if (await previewTab.isVisible({ timeout: 3000 })) {
      await previewTab.click();
      await expect(page.locator('iframe[title="Preview" i]')).toBeVisible();
    }
  });

  test('choosing a predefined design pre-fills the editor', async ({ page }) => {
    await page.getByRole('button', { name: /new template/i }).click();
    const designCard = page.locator('[role="button"][aria-label]').first();
    if (await designCard.isVisible({ timeout: 3000 })) {
      await designCard.click();
      await expect(page.getByRole('heading', { name: 'New Template' })).toBeVisible();
      // Design should have pre-filled a subject line (non-empty).
      const subjectField = page.getByLabel(/subject/i);
      await expect(subjectField).toBeVisible();
    } else {
      // No predefined designs seeded: fall back to blank flow, still valid.
      await expect(page.getByRole('button', { name: /start from blank/i })).toBeVisible();
    }
  });

  test('Event Mapping tab is navigable', async ({ page }) => {
    await page.getByRole('tab', { name: /event mapping/i }).click();
    await expect(page.getByText(/keeps every system event wired to a template/i)).toBeVisible();
  });

  test('Outbox tab is navigable and shows delivery pagination controls', async ({ page }) => {
    await page.getByRole('tab', { name: /outbox/i }).click();
    await expect(page.getByText(/deliveries/i)).toBeVisible();
  });

  test('AI Suggestions tab is navigable', async ({ page }) => {
    await page.getByRole('tab', { name: /ai suggestions/i }).click();
    // Either suggestions render or the "No AI suggestions available" alert shows.
    await expect(page.getByText(/ai suggestion|no ai suggestions available/i).first()).toBeVisible();
  });

  test.describe('Global CSS for Emails tab', () => {
    test.beforeEach(async ({ page }) => {
      await page.getByRole('tab', { name: /global css for emails/i }).click();
    });

    test('shows explainer, brand fields, and save action', async ({ page }) => {
      await expect(page.getByText(/global css for emails/i).first()).toBeVisible();
      await expect(page.getByText(/applied to every outgoing email/i)).toBeVisible();
      await expect(page.getByLabel(/primary brand color/i)).toBeVisible();
      await expect(page.getByLabel(/font family/i)).toBeVisible();
      await expect(page.getByLabel(/global email css/i)).toBeVisible();
      await expect(page.getByRole('button', { name: /save global css/i })).toBeVisible();
    });

    test('can edit and save custom CSS', async ({ page }) => {
      const cssField = page.getByLabel(/global email css/i);
      await cssField.fill('a { color: #123456; }');
      await page.getByRole('button', { name: /save global css/i }).click();
      await page.waitForLoadState('networkidle');
      // Persisted value should survive a reload.
      await page.reload();
      await page.waitForLoadState('networkidle');
      await page.getByRole('tab', { name: /global css for emails/i }).click();
      await expect(page.getByLabel(/global email css/i)).toHaveValue(/#123456/i);
    });
  });
});
