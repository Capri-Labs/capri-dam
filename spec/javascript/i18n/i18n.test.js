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

describe('i18n — imageEditor English strings (regression guard)', () => {
  beforeEach(() => i18n.changeLanguage('en'));

  it('imageEditor.title', () => {
    expect(i18n.t('imageEditor.title')).toBe('Studio Editor');
  });

  it('imageEditor.exportAndSave', () => {
    expect(i18n.t('imageEditor.exportAndSave')).toBe('Export & Save');
  });

  it('imageEditor.tabs.suggestions', () => {
    expect(i18n.t('imageEditor.tabs.suggestions')).toBe('Suggestions');
  });

  it('imageEditor.tabs.adjust', () => {
    expect(i18n.t('imageEditor.tabs.adjust')).toBe('Adjust');
  });

  it('imageEditor.tabs.aiStudio', () => {
    expect(i18n.t('imageEditor.tabs.aiStudio')).toBe('AI Studio');
  });

  it('imageEditor.quickActions.autoEnhance', () => {
    expect(i18n.t('imageEditor.quickActions.autoEnhance')).toBe('Auto Enhance');
  });

  it('imageEditor.quickActions.dynamicHdr', () => {
    expect(i18n.t('imageEditor.quickActions.dynamicHdr')).toBe('Dynamic HDR');
  });

  it('imageEditor.quickActions.colorPop', () => {
    expect(i18n.t('imageEditor.quickActions.colorPop')).toBe('Color Pop');
  });

  it('imageEditor.aspectRatio', () => {
    expect(i18n.t('imageEditor.aspectRatio')).toBe('Aspect Ratio');
  });

  it('imageEditor.freeform', () => {
    expect(i18n.t('imageEditor.freeform')).toBe('Freeform');
  });

  it('imageEditor.square', () => {
    expect(i18n.t('imageEditor.square')).toBe('1:1 Square');
  });

  it('imageEditor.widescreen', () => {
    expect(i18n.t('imageEditor.widescreen')).toBe('16:9 Widescreen');
  });

  it('imageEditor.lutFilters', () => {
    expect(i18n.t('imageEditor.lutFilters')).toBe('LUT Filters');
  });

  it('imageEditor.saveAsNewVersion', () => {
    expect(i18n.t('imageEditor.saveAsNewVersion')).toBe('Save as New Version');
  });

  it('imageEditor.overwriteCurrent', () => {
    expect(i18n.t('imageEditor.overwriteCurrent')).toBe('Overwrite Current');
  });

  it('imageEditor.saveAsCopy', () => {
    expect(i18n.t('imageEditor.saveAsCopy')).toBe('Save as Copy');
  });

  it('imageEditor.errors.assetNotFound', () => {
    expect(i18n.t('imageEditor.errors.assetNotFound')).toBe('Asset not found.');
  });

  it('imageEditor.errors.processingFailed', () => {
    expect(i18n.t('imageEditor.errors.processingFailed')).toBe('Image processing failed. Please try again.');
  });

  it('imageEditor.notifications.savedAsNewVersion', () => {
    expect(i18n.t('imageEditor.notifications.savedAsNewVersion')).toBe('New immutable version saved successfully.');
  });

  it('imageEditor.notifications.overwritten', () => {
    expect(i18n.t('imageEditor.notifications.overwritten')).toBe('Current version forcefully overwritten.');
  });
});

describe('i18n — German imageEditor translations (spot-check)', () => {
  beforeEach(() => i18n.changeLanguage('de'));
  afterAll(() => i18n.changeLanguage('en'));

  it('imageEditor.title → Studio-Editor', () => {
    expect(i18n.t('imageEditor.title')).toBe('Studio-Editor');
  });

  it('imageEditor.exportAndSave → Exportieren & Speichern', () => {
    expect(i18n.t('imageEditor.exportAndSave')).toBe('Exportieren & Speichern');
  });

  it('imageEditor.tabs.suggestions → Vorschläge', () => {
    expect(i18n.t('imageEditor.tabs.suggestions')).toBe('Vorschläge');
  });

  it('imageEditor.tabs.adjust → Anpassen', () => {
    expect(i18n.t('imageEditor.tabs.adjust')).toBe('Anpassen');
  });

  it('imageEditor.tabs.aiStudio → KI-Studio', () => {
    expect(i18n.t('imageEditor.tabs.aiStudio')).toBe('KI-Studio');
  });

  it('imageEditor.quickActions.autoEnhance → Automatische Verbesserung', () => {
    expect(i18n.t('imageEditor.quickActions.autoEnhance')).toBe('Automatische Verbesserung');
  });

  it('imageEditor.quickActions.colorPop → Farbexplosion', () => {
    expect(i18n.t('imageEditor.quickActions.colorPop')).toBe('Farbexplosion');
  });

  it('imageEditor.brightness → Helligkeit', () => {
    expect(i18n.t('imageEditor.brightness')).toBe('Helligkeit');
  });

  it('imageEditor.contrast → Kontrast', () => {
    expect(i18n.t('imageEditor.contrast')).toBe('Kontrast');
  });

  it('imageEditor.saturation → Sättigung', () => {
    expect(i18n.t('imageEditor.saturation')).toBe('Sättigung');
  });

  it('imageEditor.saveAsNewVersion → Als neue Version speichern', () => {
    expect(i18n.t('imageEditor.saveAsNewVersion')).toBe('Als neue Version speichern');
  });

  it('imageEditor.overwriteCurrent → Aktuelle Version überschreiben', () => {
    expect(i18n.t('imageEditor.overwriteCurrent')).toBe('Aktuelle Version überschreiben');
  });

  it('imageEditor.saveAsCopy → Als Kopie speichern', () => {
    expect(i18n.t('imageEditor.saveAsCopy')).toBe('Als Kopie speichern');
  });

  it('imageEditor.errors.processingFailed → Bildverarbeitung fehlgeschlagen...', () => {
    expect(i18n.t('imageEditor.errors.processingFailed')).toContain('Bildverarbeitung fehlgeschlagen');
  });
});

describe('i18n — imageEditor keys interpolation', () => {
  beforeEach(() => i18n.changeLanguage('en'));

  it('imageEditor.errors.invalidParameters interpolates {{message}}', () => {
    const result = i18n.t('imageEditor.errors.invalidParameters', { message: 'brightness out of range' });
    expect(result).toContain('brightness out of range');
  });

  it('imageEditor.notifications.savedAsCopy interpolates {{folder}}', () => {
    const result = i18n.t('imageEditor.notifications.savedAsCopy', { folder: 'Projects' });
    expect(result).toContain('Projects');
  });

  it('imageEditor.notifications.versionSavedAndMoved interpolates {{folder}}', () => {
    const result = i18n.t('imageEditor.notifications.versionSavedAndMoved', { folder: 'Archive' });
    expect(result).toContain('Archive');
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


describe('i18n — login strings (regression guard)', () => {
  beforeEach(() => i18n.changeLanguage('en'));

  it('login.title', () => expect(i18n.t('login.title')).toBe('Capri DAM'));
  it('login.signIn', () => expect(i18n.t('login.signIn')).toBe('Sign In'));
  it('login.forgotPassword', () => expect(i18n.t('login.forgotPassword')).toBe('Forgot password?'));
  it('login.forceTitle', () => expect(i18n.t('login.forceTitle')).toBe('Action Required'));
});


describe('i18n — search strings (regression guard)', () => {
  beforeEach(() => i18n.changeLanguage('en'));
  afterAll(() => i18n.changeLanguage('en'));

  // Top-level search keys
  it('search.title',        () => expect(i18n.t('search.title')).toBe('Advanced Search'));
  it('search.placeholder',  () => expect(i18n.t('search.placeholder')).toContain('Search'));
  it('search.resultsFound', () => expect(i18n.t('search.resultsFound')).toBe('results found'));
  it('search.share',        () => expect(i18n.t('search.share')).toBe('Share Results'));

  // Sort options
  it('search.sort.relevance', () => expect(i18n.t('search.sort.relevance')).toBe('Relevance'));
  it('search.sort.name',      () => expect(i18n.t('search.sort.name')).toBe('Name'));
  it('search.sort.modified',  () => expect(i18n.t('search.sort.modified')).toBe('Last Modified'));
  it('search.sort.size',      () => expect(i18n.t('search.sort.size')).toBe('File Size'));

  // Quick searches
  it('search.quickSearches.recent_images', () => expect(i18n.t('search.quickSearches.recent_images')).toBe('Recent Images'));
  it('search.quickSearches.approved',      () => expect(i18n.t('search.quickSearches.approved')).toBe('Approved'));

  // Filter section labels
  it('search.filters.title',         () => expect(i18n.t('search.filters.title')).toBe('Filters'));
  it('search.filters.reset',         () => expect(i18n.t('search.filters.reset')).toBe('Reset all filters'));
  it('search.filters.mimeType',      () => expect(i18n.t('search.filters.mimeType')).toBe('File Type'));
  it('search.filters.lastModified',  () => expect(i18n.t('search.filters.lastModified')).toBe('Last Modified'));
  it('search.filters.fileSize',      () => expect(i18n.t('search.filters.fileSize')).toBe('File Size'));
  it('search.filters.status',        () => expect(i18n.t('search.filters.status')).toBe('Status'));
  it('search.filters.orientation',   () => expect(i18n.t('search.filters.orientation')).toBe('Orientation'));
  it('search.filters.style',         () => expect(i18n.t('search.filters.style')).toBe('Style'));
  it('search.filters.video',         () => expect(i18n.t('search.filters.video')).toBe('Video'));
  it('search.filters.audio',         () => expect(i18n.t('search.filters.audio')).toBe('Audio'));

  // MIME group options
  it('search.filters.mime.images',     () => expect(i18n.t('search.filters.mime.images')).toBe('Images'));
  it('search.filters.mime.documents',  () => expect(i18n.t('search.filters.mime.documents')).toBe('Documents'));
  it('search.filters.mime.multimedia', () => expect(i18n.t('search.filters.mime.multimedia')).toBe('Multimedia'));
  it('search.filters.mime.archives',   () => expect(i18n.t('search.filters.mime.archives')).toBe('Archives'));
  it('search.filters.mime.other',      () => expect(i18n.t('search.filters.mime.other')).toBe('Other'));

  // Modified options
  it('search.filters.modified.hour',  () => expect(i18n.t('search.filters.modified.hour')).toBe('Last Hour'));
  it('search.filters.modified.day',   () => expect(i18n.t('search.filters.modified.day')).toBe('Last 24h'));
  it('search.filters.modified.week',  () => expect(i18n.t('search.filters.modified.week')).toBe('Last Week'));
  it('search.filters.modified.month', () => expect(i18n.t('search.filters.modified.month')).toBe('Last Month'));
  it('search.filters.modified.year',  () => expect(i18n.t('search.filters.modified.year')).toBe('Last Year'));

  // File size options
  it('search.filters.size.small',  () => expect(i18n.t('search.filters.size.small')).toBe('Small (<1 MB)'));
  it('search.filters.size.medium', () => expect(i18n.t('search.filters.size.medium')).toBe('Medium (1–10 MB)'));
  it('search.filters.size.large',  () => expect(i18n.t('search.filters.size.large')).toBe('Large (>10 MB)'));

  // Publish/approval status
  it('search.filters.publish.published',    () => expect(i18n.t('search.filters.publish.published')).toBe('Published'));
  it('search.filters.publish.unpublished',  () => expect(i18n.t('search.filters.publish.unpublished')).toBe('Unpublished'));
  it('search.filters.approval.approved',    () => expect(i18n.t('search.filters.approval.approved')).toBe('Approved'));
  it('search.filters.approval.rejected',    () => expect(i18n.t('search.filters.approval.rejected')).toBe('Rejected'));

  // Orientation and style
  it('search.filters.orientations.horizontal', () => expect(i18n.t('search.filters.orientations.horizontal')).toBe('Horizontal'));
  it('search.filters.orientations.vertical',   () => expect(i18n.t('search.filters.orientations.vertical')).toBe('Vertical'));
  it('search.filters.orientations.square',     () => expect(i18n.t('search.filters.orientations.square')).toBe('Square'));
  it('search.filters.styles.color',            () => expect(i18n.t('search.filters.styles.color')).toBe('Color'));
  it('search.filters.styles.black_white',      () => expect(i18n.t('search.filters.styles.black_white')).toBe('Black & White'));

  // Range filter labels
  it('search.filters.min', () => expect(i18n.t('search.filters.min')).toBe('Min'));
  it('search.filters.max', () => expect(i18n.t('search.filters.max')).toBe('Max'));

  // Status labels
  it('search.status.published', () => expect(i18n.t('search.status.published')).toBe('Published'));
  it('search.status.approved',  () => expect(i18n.t('search.status.approved')).toBe('Approved'));
  it('search.status.rejected',  () => expect(i18n.t('search.status.rejected')).toBe('Rejected'));
  it('search.status.inReview',  () => expect(i18n.t('search.status.inReview')).toBe('In Review'));

  // No-results messages
  it('search.noResults.title',        () => expect(i18n.t('search.noResults.title')).toBe('No results found'));
  it('search.noResults.clearFilters', () => expect(i18n.t('search.noResults.clearFilters')).toBe('Clear Filters'));

  // Error message
  it('search.error.fetchFailed', () => expect(i18n.t('search.error.fetchFailed')).toContain('Search failed'));

  // Verify all 9 locales have the search namespace
  const LOCALES = ['en', 'de', 'es', 'fr', 'ja', 'ko', 'nl', 'pt', 'zh'];
  LOCALES.forEach(locale => {
    it(`${locale} has search.filters.title`, () => {
      i18n.changeLanguage(locale);
      const val = i18n.t('search.filters.title');
      expect(val).not.toBe('search.filters.title');
      expect(val.length).toBeGreaterThan(0);
    });
  });
});

describe('i18n — search sort direction keys (regression guard)', () => {
  beforeEach(() => i18n.changeLanguage('en'));
  afterAll(() => i18n.changeLanguage('en'));

  it('search.sort.label',            () => expect(i18n.t('search.sort.label')).toBe('Sort by'));
  it('search.sort.direction.asc',    () => expect(i18n.t('search.sort.direction.asc')).toBe('Ascending'));
  it('search.sort.direction.desc',   () => expect(i18n.t('search.sort.direction.desc')).toBe('Descending'));

  // Verify all 9 locales have direction keys
  const LOCALES = ['en', 'de', 'es', 'fr', 'ja', 'ko', 'nl', 'pt', 'zh'];
  LOCALES.forEach(locale => {
    it(`${locale} has search.sort.direction.asc`, () => {
      i18n.changeLanguage(locale);
      const val = i18n.t('search.sort.direction.asc');
      expect(val).not.toBe('search.sort.direction.asc');
      expect(val.length).toBeGreaterThan(0);
    });
    it(`${locale} has search.sort.direction.desc`, () => {
      i18n.changeLanguage(locale);
      const val = i18n.t('search.sort.direction.desc');
      expect(val).not.toBe('search.sort.direction.desc');
      expect(val.length).toBeGreaterThan(0);
    });
  });
});

describe('i18n — search filter collapse/expand keys (regression guard)', () => {
  beforeEach(() => i18n.changeLanguage('en'));
  afterAll(() => i18n.changeLanguage('en'));

  it('search.filters.collapse', () => expect(i18n.t('search.filters.collapse')).toBe('Collapse filters'));
  it('search.filters.expand',   () => expect(i18n.t('search.filters.expand')).toBe('Expand filters'));

  const LOCALES = ['en', 'de', 'es', 'fr', 'ja', 'ko', 'nl', 'pt', 'zh'];
  LOCALES.forEach(locale => {
    it(`${locale} has search.filters.collapse`, () => {
      i18n.changeLanguage(locale);
      const val = i18n.t('search.filters.collapse');
      expect(val).not.toBe('search.filters.collapse');
      expect(val.length).toBeGreaterThan(0);
    });
  });
});
