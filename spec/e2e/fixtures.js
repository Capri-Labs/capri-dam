// Playwright fixture that captures V8 JS coverage for every test and writes an
// Istanbul-format report (HTML + lcov) via monocart-coverage-reports.
//
// Usage in a spec:
//   const { test, expect } = require('./fixtures');
//
// After the run, the Istanbul report lands in coverage-frontend/e2e.
// generate() is called once via playwright.config.js globalTeardown, not
// per-test, so the summary table is only printed once at the very end.

const { test: base, expect } = require('@playwright/test');
const MCR = require('monocart-coverage-reports');

const coverageOptions = {
  name: 'Capri DAM — Frontend E2E (Istanbul)',
  outputDir: './coverage-frontend/e2e',
  reports: ['html', 'lcovonly', 'console-summary'],
  // Only report on our own application JS, not vendored bundles.
  entryFilter: {
    '**/assets/**': true,
    '**/node_modules/**': false
  },
  sourceFilter: {
    '**/app/javascript/**': true
  }
};

// Singleton — shared across all tests in this worker process.
// Coverage data is accumulated via add() per test; generate() runs once
// in globalTeardown (see playwright.config.js) after all tests finish.
const mcr = MCR(coverageOptions);

const test = base.extend({
  autoCoverage: [
    async ({ page }, use) => {
      const supportsV8 = page.coverage && typeof page.coverage.startJSCoverage === 'function';

      if (supportsV8) {
        await page.coverage.startJSCoverage({ resetOnNavigation: false });
      }

      await use();

      if (supportsV8) {
        const jsCoverage = await page.coverage.stopJSCoverage();
        await mcr.add(jsCoverage);
      }
    },
    { auto: true }
  ]
});

module.exports = { test, expect, mcr };

