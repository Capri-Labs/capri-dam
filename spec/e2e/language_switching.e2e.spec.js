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
 */

const { test, expect } = require('./fixtures');

const BASE_URL    = process.env.BASE_URL    || 'http://localhost:3000';
const ADMIN_EMAIL = process.env.ADMIN_EMAIL || 'admin@example.com';
const ADMIN_PASS  = process.env.ADMIN_PASS  || 'Password123!';

async function login(page) {
  await page.goto(`${BASE_URL}/users/sign_in`);
  await page.waitForSelector('input[autocomplete="email"]', { timeout: 15_000 });
  await page.fill('input[autocomplete="email"]',    ADMIN_EMAIL);
  await page.fill('input[autocomplete="current-password"]', ADMIN_PASS);
  await page.click('button[type="submit"]');
  await page.waitForFunction(
    () => !document.querySelector('input[autocomplete="email"]'),
    { timeout: 15_000 },
  );
  await page.waitForLoadState('networkidle');
}

async function resetToEnglish(page) {
  await page.goto(`${BASE_URL}/profile`);
  await page.locator('[role="tab"]').filter({ hasText: /Localiz|Lokalis/i }).click();
  await page.waitForTimeout(300);

  // Click the language dropdown
  const langSelect = page.locator('[role="combobox"]').filter({ has: page.locator('[aria-label*="Language"], [aria-label*="Sprache"]') }).first();
  // Try to find the select via its label
  const localizationPanel = page.locator('[role="tabpanel"]').first();
  // Find all selects in the panel
  await localizationPanel.locator('[role="combobox"]').first().click();
  await page.locator('[role="listbox"] [role="option"]').filter({ hasText: 'English' }).click();
  await page.locator('button').filter({ hasText: /Save Preferences|Einstellungen speichern|Enregistrer/i }).click();
  await page.waitForTimeout(500);
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

  test('Language dropdown shows all 9 supported languages', async ({ page }) => {
    await login(page);
    await page.goto(`${BASE_URL}/profile`);
    await page.locator('[role="tab"]').filter({ hasText: 'Localization' }).click();
    await page.waitForTimeout(300);

    // Open the language dropdown
    await page.locator('[role="tabpanel"]').locator('[role="combobox"]').nth(1).click();
    await page.waitForSelector('[role="listbox"]', { timeout: 3_000 });

    const options = await page.locator('[role="listbox"] [role="option"]').allTextContents();
    const expected = ['English', 'Deutsch', 'Français', 'Español', 'Português', 'Nederlands', '日本語', '中文', '한국어'];
    expected.forEach(lang => {
      expect(options).toContain(lang);
    });
  });

  test('Selecting German and saving changes the sidebar to German immediately', async ({ page }) => {
    await login(page);
    await page.goto(`${BASE_URL}/profile`);
    await page.locator('[role="tab"]').filter({ hasText: 'Localization' }).click();
    await page.waitForTimeout(300);

    // Select Deutsch from the language dropdown
    const langDropdown = page.locator('[role="tabpanel"]').locator('[role="combobox"]').nth(1);
    await langDropdown.click();
    await page.locator('[role="listbox"] [role="option"]').filter({ hasText: 'Deutsch' }).click();

    // Click Save Preferences
    await page.locator('button').filter({ hasText: 'Save Preferences' }).click();

    // Wait for the save to complete (success snackbar or button state)
    await page.waitForTimeout(800);

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
    await page.goto(`${BASE_URL}/profile`);
    await page.locator('[role="tab"]').filter({ hasText: 'Localization' }).click();
    await page.waitForTimeout(300);

    const langDropdown = page.locator('[role="tabpanel"]').locator('[role="combobox"]').nth(1);
    await langDropdown.click();
    await page.locator('[role="listbox"] [role="option"]').filter({ hasText: 'Deutsch' }).click();
    await page.locator('button').filter({ hasText: 'Save Preferences' }).click();
    await page.waitForTimeout(1000);

    // Navigate to dashboard (full page reload from server)
    await page.goto(`${BASE_URL}/dashboard`);

    // The `data-language` attribute on the sidebar root should be "de"
    const lang = await page.locator('#react-sidebar-root').getAttribute('data-language');
    expect(lang).toBe('de');

    // The <html> lang attribute should be "de"
    const htmlLang = await page.locator('html').getAttribute('lang');
    expect(htmlLang).toBe('de');

    // Sidebar still shows German
    await expect(page.locator('text=Übersicht')).toBeVisible({ timeout: 5_000 });
  });

  test('Switching back to English restores all English sidebar labels', async ({ page }) => {
    await login(page);

    // First set to German
    await page.goto(`${BASE_URL}/profile`);
    await page.locator('[role="tab"]').filter({ hasText: 'Localization' }).click();
    await page.waitForTimeout(300);
    await page.locator('[role="tabpanel"]').locator('[role="combobox"]').nth(1).click();
    await page.locator('[role="listbox"] [role="option"]').filter({ hasText: 'Deutsch' }).click();
    await page.locator('button').filter({ hasText: 'Save Preferences' }).click();
    await page.waitForTimeout(800);

    // Now switch back to English
    await page.locator('[role="tabpanel"]').locator('[role="combobox"]').nth(1).click();
    await page.locator('[role="listbox"] [role="option"]').filter({ hasText: 'English' }).click();
    await page.locator('button').filter({ hasText: /Einstellungen speichern|Save Preferences/i }).click();
    await page.waitForTimeout(800);

    // Sidebar should be English again
    await expect(page.locator('text=Overview')).toBeVisible({ timeout: 5_000 });
    await expect(page.locator('text=Core Application')).toBeVisible({ timeout: 3_000 });
    // German labels must be gone
    expect(await page.locator('text=Übersicht').count()).toBe(0);
  });

  test('Profile page Localization tab labels are translated after switching to German', async ({ page }) => {
    await login(page);
    await page.goto(`${BASE_URL}/profile`);
    await page.locator('[role="tab"]').filter({ hasText: 'Localization' }).click();
    await page.waitForTimeout(300);

    const langDropdown = page.locator('[role="tabpanel"]').locator('[role="combobox"]').nth(1);
    await langDropdown.click();
    await page.locator('[role="listbox"] [role="option"]').filter({ hasText: 'Deutsch' }).click();
    await page.locator('button').filter({ hasText: 'Save Preferences' }).click();
    await page.waitForTimeout(500);

    // The tab itself should now say "Lokalisierung" (German for Localization)
    await expect(
      page.locator('[role="tab"]').filter({ hasText: 'Lokalisierung' })
    ).toBeVisible({ timeout: 3_000 });

    // "Save Preferences" button → "Einstellungen speichern"
    await expect(
      page.locator('button').filter({ hasText: 'Einstellungen speichern' })
    ).toBeVisible({ timeout: 3_000 });
  });

});

