// Playwright configuration for frontend E2E tests.
//
// These tests drive a REAL browser against a running Capri DAM server
// (default http://localhost:3000). Two coverage streams are produced from a
// single run:
//   • Frontend (Istanbul) — V8 JS coverage is collected per page and converted
//     to Istanbul HTML/lcov via monocart (see spec/e2e/fixtures.js).
//   • Backend  (Coverband) — because the requests hit the live Rails server,
//     Coverband records the exercised Ruby lines (view at /admin/coverband).
//
// Start the app first (`make dev` or `bin/rails s`), then run `make e2e-frontend`.

const { defineConfig, devices } = require('@playwright/test');

const BASE_URL = process.env.E2E_BASE_URL || 'http://localhost:3000';

module.exports = defineConfig({
  testDir: './spec/e2e',
  testMatch: '**/*.e2e.spec.js',
  timeout: 30_000,
  fullyParallel: false,
  retries: 0,
  reporter: [['list'], ['html', { outputFolder: 'coverage-frontend/playwright-report', open: 'never' }]],
  use: {
    baseURL: BASE_URL,
    headless: true,
    screenshot: 'only-on-failure',
    trace: 'retain-on-failure'
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] }
    }
  ]
});

