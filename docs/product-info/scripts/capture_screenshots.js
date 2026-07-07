'use strict';

/**
 * Screenshot capture utility for the Product Guide (docs/product-info).
 *
 * This is NOT a test — it's a documentation maintenance script that drives
 * a real browser against a running Capri DAM server (same approach as the
 * Playwright E2E suite in spec/e2e/) and saves full-page screenshots into
 * docs/product-info/images/ for use in the AsciiDoc product guide.
 *
 * Usage:
 *   1. Start the app:            bin/rails s -p 3000   (or `make dev`)
 *   2. Run this script:          node docs/product-info/scripts/capture_screenshots.js
 *
 * Re-run this whenever the UI changes meaningfully so the product guide's
 * screenshots stay current. Uses the same seeded admin credentials as the
 * E2E suite (spec/e2e/helpers/login.js) — override via E2E_EMAIL / E2E_PASSWORD.
 */

const { chromium } = require('@playwright/test');
const path = require('path');

const BASE_URL = process.env.E2E_BASE_URL || 'http://localhost:3000';
const EMAIL = process.env.E2E_EMAIL || 'admin@admin.com';
const PASSWORD = process.env.E2E_PASSWORD || 'AdminUser';
const OUT_DIR = path.join(__dirname, '..', 'images');

const SHOTS = [
  { name: 'dashboard', url: '/dashboard', wait: '#header-root' },
  { name: 'folders-browser', url: '/folders', wait: 'text=/Folders|Assets/i' },
  { name: 'search-results', url: '/search?q=logo', wait: '#header-root' },
  { name: 'collections', url: '/collections', wait: '#header-root' },
  { name: 'recycle-bin', url: '/bin', wait: 'text=/Recycle Bin/i' },
  { name: 'duplicates', url: '/duplicates', wait: '#header-root' },
  { name: 'inbox', url: '/inbox', wait: '#header-root' },
  { name: 'workflow-designer', url: '/workflows', wait: '#header-root' },
  { name: 'workflow-dashboard', url: '/workflows/dashboard', wait: '#header-root' },
  { name: 'ai-copilot', url: '/ai/copilot', wait: '#header-root' },
  { name: 'style-model-hub', url: '/ai/models/hub', wait: 'text=/Style & Model Hub/i' },
  { name: 'provenance-c2pa', url: '/ai/governance/provenance', wait: 'text=/Provenance/i' },
  { name: 'profile-localization', url: '/profile', wait: '#header-root' },
  { name: 'admin-users', url: '/admin/users', wait: 'text=/Users/i' },
  { name: 'admin-user-groups', url: '/admin/user_groups', wait: 'text=/Groups/i' },
  { name: 'admin-system-status', url: '/settings/system', wait: 'text=/System/i' },
  { name: 'operational-logging', url: '/settings/system', wait: 'text=/Operational Logging/i' },
  { name: 'audit-trail', url: '/settings/system', wait: 'text=/Audit Trail/i' },
  { name: 'admin-email-engine', url: '/admin/email_templates', wait: '#header-root' },
  { name: 'admin-ingestion-pipeline', url: '/admin/migrations/ingestion', wait: '#header-root' },
  { name: 'data-health', url: '/admin/migrations/health', wait: '#header-root' },
  { name: 'admin-reports', url: '/reports', wait: '#header-root' },
  { name: 'folder-access-acl', url: '/folders', wait: 'text=/Folders|Assets/i' },
];

// NOTE: `operational-logging`, `audit-trail`, and `folder-access-acl` land on a
// page that requires clicking into a specific tab/drawer after navigation
// (System Status tabs, or a folder's Info Panel → Access tab respectively).
// This script captures the landing page for those URLs; if you need the exact
// tab/drawer state shown in the product guide, click through manually after
// the script navigates there, or extend this script with tab-click logic.

async function login(page) {
  await page.goto(`${BASE_URL}/users/sign_in`);
  await page.waitForSelector('input[autocomplete="email"]', { timeout: 15000 });
  await page.fill('input[autocomplete="email"]', EMAIL);
  await page.fill('input[autocomplete="current-password"]', PASSWORD);
  const [response] = await Promise.all([
    page.waitForResponse((res) => res.url().includes('/users/sign_in.json'), { timeout: 15000 }),
    page.click('button[type="submit"]'),
  ]);
  if (!response.ok()) throw new Error(`login failed with status ${response.status()}`);
  await page.waitForURL(/^https?:\/\/[^/]+\/?(\?.*)?$/, { timeout: 15000 });
  await page.waitForLoadState('networkidle');
}

(async () => {
  const browser = await chromium.launch();
  const context = await browser.newContext({ viewport: { width: 1600, height: 1000 }, baseURL: BASE_URL });
  const page = await context.newPage();

  await login(page);

  for (const shot of SHOTS) {
    try {
      await page.goto(`${BASE_URL}${shot.url}`, { waitUntil: 'networkidle', timeout: 20000 });
      if (shot.wait) {
        await page.waitForSelector(shot.wait, { timeout: 8000 }).catch(() => {});
      }
      await page.waitForTimeout(600); // allow charts/animations to settle
      const outPath = path.join(OUT_DIR, `${shot.name}.png`);
      await page.screenshot({ path: outPath, fullPage: false });
      console.log(`✓ ${shot.name} -> ${outPath}`);
    } catch (err) {
      console.error(`✗ ${shot.name} failed: ${err.message}`);
    }
  }

  await browser.close();
})();
