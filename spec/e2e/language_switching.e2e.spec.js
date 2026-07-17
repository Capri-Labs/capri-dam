/**
 * Language Switching E2E — validates zero-lag i18n via the Profile page.
 *
 * Tests:
 *  1. Profile page Localization tab shows a language dropdown.
 *  2. Changing language to German and saving immediately translates the
 *     sidebar menu items (no page reload required).
 *  3. After saving, the server-side `data-language` reflects the new language
 *     on the next navigation (verifying DB persistence).
 *  4. Switching back to English restores all English labels.
 *  5. The HTML lang attribute is updated.
 *  6. Each of the remaining 7 non-German locales (Spanish, French, Japanese,
 *     Korean, Dutch, Portuguese, Chinese) switches + persists correctly
 *     (closes the "E2E coverage for the remaining 7 non-German locales" gap
 *     from docs/product-info/src/99_roadmap_and_test_coverage.adoc).
 *  7. Arabic: same switch/persist behavior, PLUS `<html dir="rtl">` is
 *     applied (closes "RTL layout verification for Arabic" — see
 *     docs/product-info/src/13_localization_i18n.adoc "Notes & known
 *     limitations"). Note: only base RTL text-direction is verified here;
 *     full MUI-component-level RTL layout mirroring is not implemented (see
 *     that doc's "Test coverage status" for the exact scope).
 */

const { test, expect } = require('./fixtures');

const BASE_URL    = process.env.BASE_URL    || 'http://localhost:3000';
const ADMIN_EMAIL = process.env.ADMIN_EMAIL || 'admin@admin.com';
const ADMIN_PASS  = process.env.ADMIN_PASS  || 'AdminUser';

async function login(page) {
  await page.goto(`${BASE_URL}/users/sign_in`);
  await page.waitForSelector('input[autocomplete="email"]', { timeout: 15_000 });
  await page.fill('input[autocomplete="email"]',    ADMIN_EMAIL);
  await page.fill('input[autocomplete="current-password"]', ADMIN_PASS);

  const [response] = await Promise.all([
    page.waitForResponse((res) => res.url().includes('/users/sign_in.json'), { timeout: 15_000 }),
    page.click('button[type="submit"]'),
  ]);
  if (!response.ok()) throw new Error(`login failed with status ${response.status()}`);

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

async function openLocalizationTab(page) {
  await page.goto(`${BASE_URL}/profile`);
  await page.getByTestId('profile-tab-localization').click();
  await page.waitForTimeout(300);
}

// The Localization tabpanel contains two comboboxes: Theme (index 0) then
// Language (index 1). Must target the Language one, not Theme.
function languageDropdown(page) {
  return page.locator('[role="tabpanel"]').first().locator('[role="combobox"]').nth(1);
}

async function selectLanguageAndSave(page, label) {
  await languageDropdown(page).click();
  await page.locator('[role="listbox"] [role="option"]').filter({ hasText: label }).click();
  await page.getByTestId('save-preferences-button').click();
  await page.waitForTimeout(800);
}

async function resetToEnglish(page) {
  await openLocalizationTab(page);
  await selectLanguageAndSave(page, 'English');
}

test.describe('Language Switching — Profile Localization Tab', () => {

  test.afterEach(async ({ page }) => {
    // Always reset to English after each test to avoid state bleed
    try { await resetToEnglish(page); } catch { /* best-effort */ }
  });

  test('Localization tab loads with a language selector', async ({ page }) => {
    await login(page);
    await page.goto(`${BASE_URL}/profile`);

    // Click the localization tab
    await page.locator('[role="tab"]').filter({ hasText: 'Localization' }).click();

    // The Interface Language dropdown should be visible
    await expect(
      page.locator('label').filter({ hasText: 'Interface Language' })
    ).toBeVisible({ timeout: 5_000 });
  });

  test('Language dropdown shows all 10 supported languages, including Arabic', async ({ page }) => {
    await login(page);
    await openLocalizationTab(page);

    // Open the language dropdown
    await languageDropdown(page).click();
    await page.waitForSelector('[role="listbox"]', { timeout: 3_000 });

    const options = await page.locator('[role="listbox"] [role="option"]').allTextContents();
    const expected = ['English', 'Deutsch', 'Français', 'Español', 'Português', 'Nederlands', '日本語', '中文', '한국어', 'العربية'];
    expected.forEach(lang => {
      expect(options).toContain(lang);
    });
  });

  test('Selecting German and saving changes the sidebar to German immediately', async ({ page }) => {
    await login(page);
    await openLocalizationTab(page);
    await selectLanguageAndSave(page, 'Deutsch');

    // The sidebar should now show German labels WITHOUT a page reload
    // "Overview" → "Übersicht"
    await expect(page.locator('#react-sidebar-root').or(page.locator('nav')).locator('text=Übersicht'))
      .toBeVisible({ timeout: 5_000 });

    // The "Core Application" group → "Kernanwendung"
    await expect(
      page.locator('text=Kernanwendung')
    ).toBeVisible({ timeout: 3_000 });
  });

  test('Saving language persists to DB — next page load uses German', async ({ page }) => {
    await login(page);
    await openLocalizationTab(page);
    await selectLanguageAndSave(page, 'Deutsch');

    // Navigate to dashboard (full page reload from server)
    await page.goto(`${BASE_URL}/dashboard`);

    // The `data-language` attribute on the sidebar root should be "de"
    const lang = await page.locator('#react-sidebar-root').getAttribute('data-language');
    expect(lang).toBe('de');

    // The <html> lang attribute should be "de"
    const htmlLang = await page.locator('html').getAttribute('lang');
    expect(htmlLang).toBe('de');

    // Sidebar still shows German
    await expect(page.getByRole('button', { name: 'Übersicht' })).toBeVisible({ timeout: 5_000 });
  });

  test('Switching back to English restores all English sidebar labels', async ({ page }) => {
    await login(page);

    // First set to German
    await openLocalizationTab(page);
    await selectLanguageAndSave(page, 'Deutsch');

    // Now switch back to English
    await selectLanguageAndSave(page, 'English');

    // Sidebar should be English again
    await expect(page.locator('text=Overview')).toBeVisible({ timeout: 5_000 });
    await expect(page.locator('text=Core Application')).toBeVisible({ timeout: 3_000 });
    // German labels must be gone
    expect(await page.locator('text=Übersicht').count()).toBe(0);
  });

  test('Profile page Localization tab labels are translated after switching to German', async ({ page }) => {
    await login(page);
    await openLocalizationTab(page);
    await selectLanguageAndSave(page, 'Deutsch');

    // The tab itself should now say "Lokalisierung" (German for Localization)
    await expect(
      page.locator('[role="tab"]').filter({ hasText: 'Lokalisierung' })
    ).toBeVisible({ timeout: 3_000 });

    // "Save Preferences" button → "Einstellungen speichern"
    await expect(
      page.getByTestId('save-preferences-button').filter({ hasText: 'Einstellungen speichern' })
    ).toBeVisible({ timeout: 3_000 });
  });

  // ── The remaining 7 non-German locales ────────────────────────────────────
  // Each entry: dropdown label, expected translated sidebar "Overview" label,
  // and the ISO code expected in `data-language`/`<html lang>` after persist.
  const remainingLocales = [
    { label: 'Español',    overview: 'Resumen',           code: 'es' },
    { label: 'Français',   overview: "Vue d'ensemble",    code: 'fr' },
    { label: '日本語',      overview: '概要',              code: 'ja' },
    { label: '한국어',      overview: '개요',              code: 'ko' },
    { label: 'Nederlands', overview: 'Overzicht',         code: 'nl' },
    { label: 'Português',  overview: 'Visão geral',       code: 'pt' },
    { label: '中文',        overview: '概述',              code: 'zh' },
  ];

  for (const { label, overview, code } of remainingLocales) {
    test(`Selecting ${label} translates the sidebar and persists (data-language="${code}")`, async ({ page }) => {
      await login(page);
      await openLocalizationTab(page);
      await selectLanguageAndSave(page, label);

      // Zero-lag: sidebar reflects the new locale without a page reload.
      await expect(page.getByRole('button', { name: overview })).toBeVisible({ timeout: 5_000 });

      // Persists server-side: a fresh navigation still uses this locale.
      await page.goto(`${BASE_URL}/dashboard`);
      await expect(page.locator('#react-sidebar-root')).toHaveAttribute('data-language', code);
      await expect(page.locator('html')).toHaveAttribute('lang', code);
      await expect(page.getByRole('button', { name: overview })).toBeVisible({ timeout: 5_000 });

      // None of these locales are RTL — base direction must stay ltr.
      await expect(page.locator('html')).toHaveAttribute('dir', 'ltr');
    });
  }

  // ── Arabic — RTL layout verification ──────────────────────────────────────
  test('Selecting Arabic sets <html dir="rtl">, persists, and applies real Arabic translations', async ({ page }) => {
    await login(page);
    await openLocalizationTab(page);
    await selectLanguageAndSave(page, 'العربية');

    // Zero-lag: dir flips to rtl immediately, without a page reload.
    await expect(page.locator('html')).toHaveAttribute('dir', 'rtl', { timeout: 5_000 });
    await expect(page.locator('html')).toHaveAttribute('lang', 'ar');

    // Persists server-side: a fresh navigation still renders RTL.
    await page.goto(`${BASE_URL}/dashboard`);
    await expect(page.locator('#react-sidebar-root')).toHaveAttribute('data-language', 'ar');
    await expect(page.locator('html')).toHaveAttribute('lang', 'ar');
    await expect(page.locator('html')).toHaveAttribute('dir', 'rtl');

    // Sanity-check a genuinely-translated Arabic string is rendered (not
    // every key in ar.json is translated yet — see the product doc's "Notes
    // & known limitations" — but "Inbox" is, and proves the pipeline works).
    await expect(page.getByText('صندوق الوارد')).toBeVisible({ timeout: 5_000 });
  });

  test('Switching from Arabic back to English restores <html dir="ltr">', async ({ page }) => {
    await login(page);
    await openLocalizationTab(page);
    await selectLanguageAndSave(page, 'العربية');
    await expect(page.locator('html')).toHaveAttribute('dir', 'rtl', { timeout: 5_000 });

    await selectLanguageAndSave(page, 'English');
    await expect(page.locator('html')).toHaveAttribute('dir', 'ltr', { timeout: 5_000 });
    await expect(page.locator('html')).toHaveAttribute('lang', 'en');
  });

});
