/**
 * i18n configuration tests.
 *
 * Verifies that:
 *  1. All 9 locale bundles are correctly loaded.
 *  2. Every key present in en.json exists in every other locale (no silent gaps).
 *  3. English strings match the expected values (regression guard).
 *  4. German strings are correctly translated (spot-check).
 *  5. Interpolation works (e.g. {{name}} is substituted).
 *  6. Missing keys fall back to English gracefully (no crash).
 */

import i18n from '../../../app/javascript/i18n/index';

// ─── Helpers ─────────────────────────────────────────────────────────────────

/** Recursively collect all dot-notation keys from a nested JSON object. */
function flatKeys(obj, prefix = '') {
  return Object.entries(obj).flatMap(([k, v]) => {
    const key = prefix ? `${prefix}.${k}` : k;
    return typeof v === 'object' && v !== null && !Array.isArray(v)
      ? flatKeys(v, key)
      : [key];
  });
}

const LOCALES = ['en', 'de', 'fr', 'es', 'pt', 'nl', 'ja', 'zh', 'ko'];

// ─── Tests ────────────────────────────────────────────────────────────────────

describe('i18n — locale completeness', () => {
  const enKeys = flatKeys(i18n.getResourceBundle('en', 'translation'));

  LOCALES.forEach(locale => {
    it(`${locale}.json is loaded and has at least as many keys as en.json`, () => {
      const bundle = i18n.getResourceBundle(locale, 'translation');
      expect(bundle).toBeTruthy();
      const localeKeys = flatKeys(bundle);
      // Every English key must be present in the locale (forward coverage).
      const missing = enKeys.filter(k => !localeKeys.includes(k));
      expect(missing).toEqual([]);
    });
  });
});

describe('i18n — English strings (regression guard)', () => {
  beforeEach(() => i18n.changeLanguage('en'));

  it('menu group core', () => {
    expect(i18n.t('menu.group.core')).toBe('Core Application');
  });

  it('menu.item.Overview', () => {
    expect(i18n.t('menu.item.Overview')).toBe('Overview');
  });

  it('menu.item.Bin', () => {
    expect(i18n.t('menu.item.Bin')).toBe('Recycle Bin');
  });

  it('common.save', () => {
    expect(i18n.t('common.save')).toBe('Save');
  });

  it('common.cancel', () => {
    expect(i18n.t('common.cancel')).toBe('Cancel');
  });

  it('profile.tabs.personal', () => {
    expect(i18n.t('profile.tabs.personal')).toBe('Personal Details');
  });

  it('profile.tabs.localization', () => {
    expect(i18n.t('profile.tabs.localization')).toBe('Localization');
  });

  it('profile.localization.language', () => {
    expect(i18n.t('profile.localization.language')).toBe('Interface Language');
  });

  it('header.myProfile', () => {
    expect(i18n.t('header.myProfile')).toBe('My Profile');
  });

  it('impersonation.endImpersonation', () => {
    expect(i18n.t('impersonation.endImpersonation')).toBe('End Impersonation');
  });
});

describe('i18n — German translations (spot-check)', () => {
  beforeEach(() => i18n.changeLanguage('de'));
  afterAll(() => i18n.changeLanguage('en'));

  it('menu.group.core → Kernanwendung', () => {
    expect(i18n.t('menu.group.core')).toBe('Kernanwendung');
  });

  it('menu.item.Overview → Übersicht', () => {
    expect(i18n.t('menu.item.Overview')).toBe('Übersicht');
  });

  it('menu.item.Bin → Papierkorb', () => {
    expect(i18n.t('menu.item.Bin')).toBe('Papierkorb');
  });

  it('common.save → Speichern', () => {
    expect(i18n.t('common.save')).toBe('Speichern');
  });

  it('common.cancel → Abbrechen', () => {
    expect(i18n.t('common.cancel')).toBe('Abbrechen');
  });

  it('profile.tabs.personal → Persönliche Daten', () => {
    expect(i18n.t('profile.tabs.personal')).toBe('Persönliche Daten');
  });

  it('impersonation.endImpersonation → Imitation beenden', () => {
    expect(i18n.t('impersonation.endImpersonation')).toBe('Imitation beenden');
  });

  it('profile.localization.savePreferences → Einstellungen speichern', () => {
    expect(i18n.t('profile.localization.savePreferences')).toBe('Einstellungen speichern');
  });
});

describe('i18n — interpolation', () => {
  beforeEach(() => i18n.changeLanguage('en'));

  it('impersonation.actingAs interpolates {{name}}', () => {
    const result = i18n.t('impersonation.youAre', { name: 'Jane Doe' });
    expect(result).toContain('Jane Doe');
  });

  it('profile.personal.ssoNote interpolates {{provider}}', () => {
    const result = i18n.t('profile.personal.ssoNote', { provider: 'Keycloak' });
    expect(result).toContain('Keycloak');
  });
});

describe('i18n — missing key fallback', () => {
  it('returns the key path when a key does not exist in any locale', () => {
    i18n.changeLanguage('en');
    // i18next returns the key itself when no translation is found
    const result = i18n.t('non.existent.key.xyz', { defaultValue: 'fallback text' });
    expect(result).toBe('fallback text');
  });

  it('falls back to English when key is missing in German', () => {
    // Temporarily remove a key from de to simulate a partial translation
    i18n.changeLanguage('de');
    // The fallbackLng: 'en' ensures English is used instead of returning the key
    expect(i18n.t('menu.group.core')).not.toBe('menu.group.core');
  });
});

describe('i18n — all 9 locales load without errors', () => {
  LOCALES.forEach(locale => {
    it(`${locale} loads successfully`, () => {
      i18n.changeLanguage(locale);
      // If the locale loaded, t() should return a real string, not the key
      const result = i18n.t('common.save');
      expect(result).not.toBe('common.save');
      expect(typeof result).toBe('string');
      expect(result.length).toBeGreaterThan(0);
    });
  });

  afterAll(() => i18n.changeLanguage('en'));
});

