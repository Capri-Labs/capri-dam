/**
 * i18n — i18next initialization for the Capri DAM frontend.
 *
 * Architecture:
 * ─────────────────────────────────────────────────────────────────────────────
 * ALL locale bundles are statically imported at build time by esbuild/Webpack.
 * This gives us:
 *   • Zero-lag language switching   — no network round-trips after initial load.
 *   • Graceful degradation          — missing keys fall back to English strings.
 *   • Source-controlled translations — auditable via Git history.
 *   • No type crashes               — React always has a string to render.
 *
 * Language selection priority (highest → lowest):
 *   1. `data-language` on the page root element  (set by Rails from user prefs)
 *   2. `localStorage.dam_language`               (persisted after in-app change)
 *   3. Browser navigator.language                (navigator default)
 *   4. Hardcoded fallback: 'en'
 * ─────────────────────────────────────────────────────────────────────────────
 *
 * Usage in components:
 *   import { useTranslation } from 'react-i18next';
 *   const { t } = useTranslation();
 *   t('menu.item.Overview')           // → "Übersicht" in German
 *   t('common.save')                  // → "Speichern" in German
 *   t('header.actingAs', { name: 'Jane' })  // interpolation
 */

import i18n from 'i18next';
import { initReactI18next } from 'react-i18next';

// ── Static locale bundles ─────────────────────────────────────────────────────
// Imported at build time: no async network request required.
import en from './locales/en.json';
import de from './locales/de.json';
import fr from './locales/fr.json';
import es from './locales/es.json';
import pt from './locales/pt.json';
import nl from './locales/nl.json';
import ja from './locales/ja.json';
import zh from './locales/zh.json';
import ko from './locales/ko.json';
import ar from './locales/ar.json';

/** All supported language codes — must match UserPreference::SUPPORTED_LANGUAGES */
export const SUPPORTED_LANGUAGES = ['en', 'de', 'fr', 'es', 'pt', 'nl', 'ja', 'zh', 'ko', 'ar'];

const resources = {
  en: { translation: en },
  de: { translation: de },
  fr: { translation: fr },
  es: { translation: es },
  pt: { translation: pt },
  nl: { translation: nl },
  ja: { translation: ja },
  zh: { translation: zh },
  ko: { translation: ko },
  ar: { translation: ar },
};

/**
 * Reads the initial language from the DOM.
 *
 * Rails injects `data-language` on the page root element so the language is
 * available synchronously on the very first render — no flash of English text.
 */
function detectInitialLanguage() {
  // 1. Rails server-rendered language (from user preference in DB)
  const root = document.getElementById('root') || document.querySelector('[data-language]');
  const serverLang = root?.dataset?.language;
  if (serverLang && SUPPORTED_LANGUAGES.includes(serverLang)) return serverLang;

  // 2. Last in-app language change persisted to localStorage
  const stored = typeof localStorage !== 'undefined' && localStorage.getItem('dam_language');
  if (stored && SUPPORTED_LANGUAGES.includes(stored)) return stored;

  // 3. Browser navigator
  const browserLang = navigator?.language?.split('-')[0];
  if (browserLang && SUPPORTED_LANGUAGES.includes(browserLang)) return browserLang;

  // 4. Hardcoded fallback
  return 'en';
}

/** Languages that read right-to-left — drives the `dir` attribute on <html>. */
const RTL_LANGUAGES = ['ar'];

/**
 * Applies `lang`/`dir` to the document root so native text-direction/layout
 * (flexbox row order, logical CSS properties, scrollbars, etc.) follows the
 * active language without requiring a full MUI RTL theme plugin.
 */
function applyDocumentDirection(lang) {
  if (typeof document === 'undefined') return;
  document.documentElement.lang = lang;
  document.documentElement.dir = RTL_LANGUAGES.includes(lang) ? 'rtl' : 'ltr';
}

i18n
  .use(initReactI18next)
  .init({
    resources,
    lng:         detectInitialLanguage(),
    fallbackLng: 'en',

    interpolation: {
      // React already escapes by default — no need for i18next to escape too.
      escapeValue: false,
    },

    // Flat key namespace — all strings live under 'translation' (default).
    defaultNS: 'translation',

    // When a key is missing in the active locale, log a warning to the console
    // in development, but NEVER break the UI — always show the fallback (English).
    missingKeyHandler: (lngs, ns, key) => {
      if (process.env.NODE_ENV === 'development') {
        console.warn(`[i18n] Missing key "${key}" for locale "${lngs.join(', ')}"`);
      }
    },
  });

// Keep <html dir>/<html lang> in sync with the active language on every
// change (Turbo page loads already get the right value server-side from
// application.html.erb; this covers the zero-lag in-app switch case).
applyDocumentDirection(i18n.language);
i18n.on('languageChanged', applyDocumentDirection);

/**
 * Switches the active language and persists the choice to localStorage so
 * that the next server-rendered page load before the server has caught up
 * still feels instant.
 *
 * Callers: ProfilePage language dropdown.
 *
 * @param {string} lang - IETF language tag, e.g. 'de'
 */
export function changeLanguage(lang) {
  if (!SUPPORTED_LANGUAGES.includes(lang)) return;
  i18n.changeLanguage(lang);
  try { localStorage.setItem('dam_language', lang); } catch { /* ignore quota errors */ }
}

export default i18n;

