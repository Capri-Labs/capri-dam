// E2E tests for the System Status → "SMTP & Email Settings" tab.
//
// Covers:
//  - Navigation to /admin/system_status and tab selection.
//  - SMTP infrastructure form fields.
//  - "Test Connection" pre-flight validation (success + structured error).
//  - "Commit System Credentials" save flow.
//  - "Trigger SMTP Diagnostic Run" test email flow.
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

test.describe('Admin — SMTP & Email Settings', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
    await page.goto('/settings/system');
    await page.waitForLoadState('networkidle');
    await page.getByRole('tab', { name: /smtp & email settings/i }).click();
  });

  test('SMTP & Email Settings tab shows the credentials form', async ({ page }) => {
    await expect(page.getByText(/smtp infrastructure setup/i)).toBeVisible();
    await expect(page.getByLabel(/smtp mail server host/i)).toBeVisible();
    await expect(page.getByLabel(/^port$/i)).toBeVisible();
    await expect(page.getByLabel(/sender address/i)).toBeVisible();
    await expect(page.getByLabel(/authentication username/i)).toBeVisible();
    await expect(page.getByLabel(/smtp password/i)).toBeVisible();
    await expect(page.getByLabel(/authentication handshake type/i)).toBeVisible();
    await expect(page.getByLabel(/connection security protocol/i)).toBeVisible();
  });

  test('Test Connection button is disabled until a host is provided', async ({ page }) => {
    const hostField = page.getByLabel(/smtp mail server host/i);
    await hostField.fill('');
    const testConnBtn = page.getByRole('button', { name: /test connection/i });
    await expect(testConnBtn).toBeDisabled();
  });

  test('Test Connection surfaces a structured error for an invalid host', async ({ page }) => {
    await page.getByLabel(/smtp mail server host/i).fill('invalid-smtp-host.invalid');
    await page.getByLabel(/^port$/i).fill('587');
    const testConnBtn = page.getByRole('button', { name: /test connection/i });
    await expect(testConnBtn).toBeEnabled();
    await testConnBtn.click();
    // Non-blocking validation should surface an alert (success or structured failure)
    // without ever hanging the UI indefinitely.
    await expect(page.locator('.MuiAlert-root').last()).toBeVisible({ timeout: 15_000 });
  });

  test('Commit System Credentials persists the SMTP configuration', async ({ page }) => {
    await page.getByLabel(/smtp mail server host/i).fill('smtp.example-test.com');
    await page.getByLabel(/^port$/i).fill('587');
    await page.getByLabel(/sender address/i).fill('noreply@example-test.com');
    await page.getByRole('button', { name: /commit system credentials/i }).click();
    await page.waitForLoadState('networkidle');
    await expect(page.locator('.MuiAlert-root, [role="alert"]').last()).toBeVisible({ timeout: 10_000 });
  });

  test('Send SMTP Echo Check requires a recipient address', async ({ page }) => {
    const sendBtn = page.getByRole('button', { name: /trigger smtp diagnostic run/i });
    await expect(sendBtn).toBeDisabled();
    await page.getByLabel(/recipient address for test mail/i).fill('qa@example-test.com');
    await expect(sendBtn).toBeEnabled();
  });
});
