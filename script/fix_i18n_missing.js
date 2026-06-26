#!/usr/bin/env node
// Fix missing i18n keys across all non-English locale files.
const fs = require('fs');
const path = require('path');

const BASE = path.join(__dirname, '..', 'app', 'javascript', 'i18n', 'locales');

const MISSING = {
  de: {
    'common.refresh':                          'Aktualisieren',
    'duplicateManager.resolution.deleting':    'Wird gel\u00F6scht\u2026',
    'duplicateManager.resolution.confirmDelete': '{{count}} Asset(s) l\u00F6schen?',
  },
  es: {
    'duplicateManager.resolution.deleting':    'Eliminando\u2026',
    'duplicateManager.resolution.confirmDelete': '\u00BFEliminar {{count}} activo(s)?',
  },
  fr: {
    'duplicateManager.resolution.deleting':    'Suppression\u2026',
    'duplicateManager.resolution.confirmDelete': 'Supprimer {{count}} \u00E9l\u00E9ment(s)\u00A0?',
  },
  ja: {
    'duplicateManager.resolution.deleting':    '\u524A\u9664\u4E2D\u2026',
    'duplicateManager.resolution.confirmDelete': '{{count}} \u4EF6\u306E\u30A2\u30BB\u30C3\u30C8\u3092\u524A\u9664\u3057\u307E\u3059\u304B\uFF1F',
  },
  ko: {
    'duplicateManager.resolution.deleting':    '\uC0AD\uC81C \uC911\u2026',
    'duplicateManager.resolution.confirmDelete': '{{count}}\uAC1C\uC758 \uC790\uC0B0\uC744 \uC0AD\uC81C\uD558\uC2DC\uACA0\uC2B5\uB2C8\uAE4C?',
  },
  nl: {
    'duplicateManager.resolution.deleting':    'Verwijderen\u2026',
    'duplicateManager.resolution.confirmDelete': '{{count}} asset(s) verwijderen?',
  },
  pt: {
    'duplicateManager.resolution.deleting':    'Excluindo\u2026',
    'duplicateManager.resolution.confirmDelete': 'Excluir {{count}} ativo(s)?',
  },
  zh: {
    'duplicateManager.resolution.deleting':    '\u5220\u9664\u4E2D\u2026',
    'duplicateManager.resolution.confirmDelete': '\u786E\u8BA4\u5220\u9664 {{count}} \u4E2A\u8D44\u4EA7\uFF1F',
  },
};

function setDeep(obj, dotKey, value) {
  const parts = dotKey.split('.');
  let cur = obj;
  for (let i = 0; i < parts.length - 1; i++) {
    if (!cur[parts[i]] || typeof cur[parts[i]] !== 'object') cur[parts[i]] = {};
    cur = cur[parts[i]];
  }
  const last = parts[parts.length - 1];
  if (cur[last] === undefined) cur[last] = value;
}

Object.entries(MISSING).forEach(([locale, keys]) => {
  const filePath = path.join(BASE, `${locale}.json`);
  const data = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  Object.entries(keys).forEach(([k, v]) => setDeep(data, k, v));
  fs.writeFileSync(filePath, JSON.stringify(data, null, 2) + '\n');
  console.log(`Updated ${locale}.json`);
});
console.log('Done.');

