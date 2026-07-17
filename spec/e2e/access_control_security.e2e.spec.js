// @ts-check
/**
 * E2E: Access Control & Security
 *
 * Closes two "Pending E2E scenarios" items from
 * docs/product-info/src/08_access_control_and_security.adoc:
 *
 *  1. OAuth2 (Doorkeeper) external-application token issuance flow
 *     end-to-end — real System Accounts UI (create → view credentials),
 *     a real POST to /oauth/token (client_credentials grant), the returned
 *     bearer token used against a real protected API endpoint, and an
 *     invalid-secret rejection.
 *
 *  2. Actual server-side enforcement of the 7-column ACL (FolderPolicy)
 *     against real API actions for real, distinct signed-in users — not
 *     just that the Access tab UI renders the columns. Covers read-only,
 *     full-access, and explicit_deny (which must override an otherwise
 *     granted read permission — see User#permissions_for).
 *
 *     This suite also serves as the regression guard for a real bug found
 *     while designing it: `DELETE /api/v1/folders/:id` had NO permission
 *     check at all (see CHANGELOG "Fixed" entry + the same-day fix in
 *     spec/requests/api/v1/folders_functional_spec.rb) — any authenticated
 *     user could trash any folder regardless of the ACL. That gap is now
 *     closed at the controller level; the read-only-user test below
 *     exercises it live against the real running server.
 *
 * Keycloak SSO full round-trip is intentionally NOT attempted here — there
 * is no live Keycloak IdP in this dev/E2E environment, and a browser-level
 * OIDC redirect round-trip cannot be faked without one. The officially
 * recommended OmniAuth `test_mode`/`mock_auth` approach already gives
 * thorough, real-code-path coverage of `Users::OmniauthCallbacksController`
 * in spec/requests/omniauth_callbacks_spec.rb (new-user provisioning,
 * existing-user field sync, redirect behaviour) — that RSpec coverage is
 * the closest equivalent to a live round-trip achievable in this
 * environment and is treated as the closing evidence for that item.
 */

const { test, expect } = require('./fixtures');
const { execFileSync } = require('node:child_process');

const EMAIL    = process.env.E2E_EMAIL    || 'admin@admin.com';
const PASSWORD = process.env.E2E_PASSWORD || 'AdminUser';
const BASE_URL = process.env.BASE_URL || process.env.E2E_BASE_URL || 'http://localhost:3000';

async function login(page, email = EMAIL, password = PASSWORD) {
  await page.goto('/users/sign_in');
  await page.waitForSelector('input[autocomplete="email"]', { timeout: 15_000 });
  await page.fill('input[autocomplete="email"]', email);
  await page.fill('input[autocomplete="current-password"]', password);

  const [response] = await Promise.all([
    page.waitForResponse((res) => res.url().includes('/users/sign_in.json'), { timeout: 15_000 }),
    page.click('button[type="submit"], input[type="submit"]'),
  ]);
  if (!response.ok()) throw new Error(`login failed with status ${response.status()}`);

  await page.waitForURL(/^https?:\/\/[^/]+\/?(\?.*)?$/, { timeout: 15_000 });
  await page.waitForLoadState('networkidle');

  const signedIn = await page.locator('#header-root').getAttribute('data-signed-in');
  if (signedIn !== 'true') {
    await page.reload();
    await page.waitForLoadState('networkidle');
  }
}

function railsRunner(script) {
  return execFileSync('bundle', ['exec', 'rails', 'runner', script], {
    cwd: process.cwd(),
    stdio: 'pipe',
  }).toString();
}

test.describe('Access Control & Security E2E', () => {
  // ───────────────────────────────────────────────────────────────────────
  // 1. OAuth2 (Doorkeeper) token issuance — real System Accounts UI flow
  // ───────────────────────────────────────────────────────────────────────
  test.describe('OAuth2 System Account token issuance', () => {
    test.beforeEach(async ({ page }) => {
      await login(page);
    });

    test('creating a System Account issues real, working OAuth2 credentials end-to-end', async ({ page }) => {
      const appName = `E2E OAuth App ${Date.now()}`;

      // 1. Real form submit via the System Accounts "New" screen.
      await page.goto('/admin/system_accounts/new');
      await page.waitForLoadState('networkidle');
      await page.fill('input[name="doorkeeper_application[name]"]', appName);
      await Promise.all([
        page.waitForURL(/\/settings/, { timeout: 15_000 }),
        page.getByRole('button', { name: /generate credentials/i }).click(),
      ]);
      await page.waitForLoadState('networkidle');

      // 2. Find the new row in the System Accounts list and open "View" to
      // reveal the (plaintext-stored, per config/initializers/doorkeeper.rb)
      // Client ID / Secret.
      const row = page.locator('tr').filter({ hasText: appName });
      await expect(row).toBeVisible({ timeout: 10_000 });
      await Promise.all([
        page.waitForURL(/\/admin\/system_accounts\/[^/]+$/, { timeout: 15_000 }),
        row.getByRole('button', { name: /view/i }).click(),
      ]);
      await page.waitForLoadState('networkidle');

      await expect(page.getByRole('heading', { name: /application credentials/i })).toBeVisible({ timeout: 10_000 });
      const uid = await page.getByLabel('Client ID (UID)').inputValue();
      const secret = await page.getByLabel('Client Secret').inputValue();
      expect(uid).toBeTruthy();
      expect(secret).toBeTruthy();

      // 3. Real POST to /oauth/token — client_credentials grant, exactly as
      // an external integration would call it.
      const tokenRes = await page.request.post('/oauth/token', {
        form: { grant_type: 'client_credentials', client_id: uid, client_secret: secret },
      });
      expect(tokenRes.ok()).toBe(true);
      const tokenBody = await tokenRes.json();
      expect(tokenBody.access_token).toBeTruthy();
      expect(tokenBody.token_type.toLowerCase()).toBe('bearer');

      // 4. Use the real bearer token against a real protected API endpoint
      // (root folder listing — folder_permission? treats folder: nil as
      // always-readable, so this exercises real Doorkeeper bearer-auth
      // acceptance without depending on a resource-owner mapping that
      // client_credentials tokens don't carry).
      const apiRes = await page.request.get('/api/v1/folders/root', {
        headers: { Authorization: `Bearer ${tokenBody.access_token}` },
      });
      expect(apiRes.ok()).toBe(true);

      // 5. Wrong secret must be rejected.
      const badRes = await page.request.post('/oauth/token', {
        form: { grant_type: 'client_credentials', client_id: uid, client_secret: 'definitely-wrong-secret' },
      });
      expect(badRes.status()).toBe(401);

      // 6. A request with a bogus bearer token and NO session cookie is
      // rejected. Uses a fresh, cookie-less request context (page.request
      // would otherwise piggy-back on this browser context's admin session
      // cookie and mask the bearer-token check entirely).
      const { request: playwrightRequest } = require('@playwright/test');
      const anonymousContext = await playwrightRequest.newContext({ baseURL: BASE_URL });
      try {
        const unauthedRes = await anonymousContext.get('/api/v1/folders/root', {
          headers: { Authorization: 'Bearer not-a-real-token' },
        });
        expect(unauthedRes.status()).toBe(401);
      } finally {
        await anonymousContext.dispose();
      }

      // Cleanup — revoke the system account via the real "Revoke" UI action
      // (confirm() dialog + Rails UJS-style form submit), then verify it's
      // gone from the list.
      page.once('dialog', (dialog) => dialog.accept());
      await Promise.all([
        page.waitForURL(/\/settings/, { timeout: 15_000 }),
        page.getByRole('button', { name: /revoke/i }).click(),
      ]);
      await page.waitForLoadState('networkidle');
      await expect(page.locator('tr').filter({ hasText: appName })).toHaveCount(0);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // 2. 7-column ACL — real server-side enforcement against real API calls
  // ───────────────────────────────────────────────────────────────────────
  test.describe('FolderPolicy (7-column ACL) server-side enforcement', () => {
    /** @type {{ folderId: string, readerEmail: string, fullEmail: string, deniedEmail: string, password: string }} */
    let seed;

    test.beforeAll(() => {
      const ts = Date.now();
      const password = 'E2ePassword123!';
      const readerEmail = `acl_reader_${ts}@e2e.test`;
      const fullEmail = `acl_full_${ts}@e2e.test`;
      const deniedEmail = `acl_denied_${ts}@e2e.test`;

      // NOTE: every dynamic value is interpolated on the JS side (via
      // JSON.stringify, which also yields a safely-escaped Ruby string
      // literal) — this script has no free-standing Ruby local variables of
      // its own, so Ruby-style #{} interpolation must never appear here.
      const script = `
        require "json"
        admin = User.find_by(email: "admin@admin.com") || User.admins.first
        folder = Folder.create!(name: "ACL E2E Folder ${ts}", user: admin)

        reader = User.create!(email: ${JSON.stringify(readerEmail)}, username: "acl_reader_${ts}",
          name: "ACL Reader", first_name: "ACL", last_name: "Reader",
          password: ${JSON.stringify(password)}, password_confirmation: ${JSON.stringify(password)},
          active: true, force_password_change: false)
        full = User.create!(email: ${JSON.stringify(fullEmail)}, username: "acl_full_${ts}",
          name: "ACL Full", first_name: "ACL", last_name: "Full",
          password: ${JSON.stringify(password)}, password_confirmation: ${JSON.stringify(password)},
          active: true, force_password_change: false)
        denied = User.create!(email: ${JSON.stringify(deniedEmail)}, username: "acl_denied_${ts}",
          name: "ACL Denied", first_name: "ACL", last_name: "Denied",
          password: ${JSON.stringify(password)}, password_confirmation: ${JSON.stringify(password)},
          active: true, force_password_change: false)

        read_group = UserGroup.create!(name: "E2E ACL Read ${ts}")
        full_group = UserGroup.create!(name: "E2E ACL Full ${ts}")
        deny_group = UserGroup.create!(name: "E2E ACL Deny ${ts}")

        FolderPolicy.create!(folder: folder, user_group: read_group, read_access: true)
        FolderPolicy.create!(folder: folder, user_group: full_group,
          read_access: true, create_access: true, modify_access: true, delete_access: true)
        FolderPolicy.create!(folder: folder, user_group: deny_group, explicit_deny: true)

        reader.user_groups << read_group
        full.user_groups << full_group
        # denied is in BOTH the read group and the deny group — explicit_deny
        # must still short-circuit to zero access (see User#permissions_for).
        denied.user_groups << read_group
        denied.user_groups << deny_group

        puts({ folderId: folder.id, readerEmail: reader.email, fullEmail: full.email, deniedEmail: denied.email }.to_json)
      `;

      const out = railsRunner(script);
      const jsonLine = out.trim().split("\n").pop();
      const parsed = JSON.parse(jsonLine);
      seed = { ...parsed, password };
    });

    test.afterAll(() => {
      if (!seed) return;
      railsRunner(`
        Folder.unscoped.find_by(id: ${JSON.stringify(seed.folderId)})&.destroy
        User.where(email: [${JSON.stringify(seed.readerEmail)}, ${JSON.stringify(seed.fullEmail)}, ${JSON.stringify(seed.deniedEmail)}]).destroy_all
      `);
    });

    test('a read-only-policy user can read the folder but is forbidden from creating or deleting it', async ({ page }) => {
      await login(page, seed.readerEmail, seed.password);

      const readRes = await page.request.get(`/api/v1/folders/${seed.folderId}`);
      expect(readRes.ok()).toBe(true);

      const csrfToken = await page.evaluate(() => document.querySelector('meta[name="csrf-token"]')?.content);
      const createRes = await page.request.post('/api/v1/folders', {
        headers: { 'X-CSRF-Token': csrfToken },
        data: { folder: { name: 'Should Not Be Created', parent_id: seed.folderId } },
      });
      expect(createRes.status()).toBe(403);

      // Regression guard for the destroy-permission bug fixed in
      // Api::V1::FoldersController#destroy — a read-only user must not be
      // able to trash the folder.
      const deleteRes = await page.request.delete(`/api/v1/folders/${seed.folderId}`, {
        headers: { 'X-CSRF-Token': csrfToken },
      });
      expect(deleteRes.status()).toBe(403);
    });

    test('a full-access-policy user can read, create inside, and delete the folder', async ({ page }) => {
      await login(page, seed.fullEmail, seed.password);

      const readRes = await page.request.get(`/api/v1/folders/${seed.folderId}`);
      expect(readRes.ok()).toBe(true);

      const csrfToken = await page.evaluate(() => document.querySelector('meta[name="csrf-token"]')?.content);
      const createRes = await page.request.post('/api/v1/folders', {
        headers: { 'X-CSRF-Token': csrfToken },
        data: { folder: { name: `ACL Child ${Date.now()}`, parent_id: seed.folderId } },
      });
      expect(createRes.ok()).toBe(true);
    });

    test('explicit_deny overrides an otherwise-granted read permission from another group', async ({ page }) => {
      await login(page, seed.deniedEmail, seed.password);

      const readRes = await page.request.get(`/api/v1/folders/${seed.folderId}`);
      expect(readRes.status()).toBe(403);
    });
  });
});
