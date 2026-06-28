// E2E tests for the Visual Workflow Designer – node drag-and-drop,
// configuration, and save flow.
//
// Requires the Rails server to be running:
//   bin/dev  (or make dev)
//
// Run:
//   yarn playwright test spec/e2e/workflow_designer.e2e.spec.js

const { test, expect } = require('./fixtures');

const BASE = process.env.APP_URL || 'http://localhost:3000';

// ─── helpers ──────────────────────────────────────────────────────────────────

async function loginAsAdmin(page) {
  await page.goto(`${BASE}/admin/login`);
  // The test suite uses the seeded admin credentials.
  await page.fill('[name="user[email]"]', process.env.ADMIN_EMAIL || 'admin@example.com');
  await page.fill('[name="user[password]"]', process.env.ADMIN_PASSWORD || 'password');
  await page.click('[type="submit"]');
  await page.waitForURL(`${BASE}/dashboard`, { timeout: 10_000 });
}

async function openWorkflowDesigner(page) {
  await page.goto(`${BASE}/workflows/new`);
  await page.waitForSelector('[data-testid="workflow-canvas"], .react-flow', { timeout: 15_000 });
}

// ─── Tests ────────────────────────────────────────────────────────────────────

test.describe('Workflow Designer — node palette', () => {
  test.beforeEach(async ({ page }) => {
    await loginAsAdmin(page);
    await openWorkflowDesigner(page);
  });

  test('shows all 6 toolbox categories', async ({ page }) => {
    for (const cat of ['Approval & Review', 'Notifications', 'Integrations', 'Asset Operations', 'AI & Processing', 'Flow Control']) {
      await expect(page.locator(`text=${cat}`).first()).toBeVisible();
    }
  });

  test('palette search filters nodes', async ({ page }) => {
    await page.fill('input[placeholder="Search…"]', 'webhook');
    await expect(page.locator('text=Webhook').first()).toBeVisible();
    await expect(page.locator('text=Send Email')).not.toBeVisible();
    // Clear search
    await page.fill('input[placeholder="Search…"]', '');
  });
});

test.describe('Workflow Designer — canvas drag-and-drop', () => {
  test.beforeEach(async ({ page }) => {
    await loginAsAdmin(page);
    await openWorkflowDesigner(page);
  });

  test('drops an Email node onto the canvas', async ({ page }) => {
    const emailItem = page.locator('text=Send Email').first();
    const canvas    = page.locator('.react-flow__pane');

    await emailItem.dragTo(canvas, {
      sourcePosition: { x: 5, y: 5 },
      targetPosition: { x: 400, y: 300 },
    });

    // The dropped node header should appear
    await expect(page.locator('text=Send Email').nth(1)).toBeVisible({ timeout: 5_000 });
  });

  test('drops a Condition node and shows TRUE/FALSE branch labels', async ({ page }) => {
    const condItem = page.locator('text=Condition Branch').first();
    const canvas   = page.locator('.react-flow__pane');

    await condItem.dragTo(canvas, {
      sourcePosition: { x: 5, y: 5 },
      targetPosition: { x: 400, y: 300 },
    });

    await expect(page.locator('text=TRUE')).toBeVisible({ timeout: 5_000 });
    await expect(page.locator('text=FALSE')).toBeVisible({ timeout: 5_000 });
  });
});

test.describe('Workflow Designer — blueprint save', () => {
  test.beforeEach(async ({ page }) => {
    await loginAsAdmin(page);
    await openWorkflowDesigner(page);
  });

  test('no longer shows the removed System-Wide Escalation block', async ({ page }) => {
    // The workflow-level escalation panel was removed in the Designer v2 refactor;
    // escalation is now configured per ApprovalNode instead.
    await expect(page.locator('text=System-Wide Escalation')).toHaveCount(0);
    await expect(page.locator('text=Fallback User')).toHaveCount(0);
  });

  test('renders the redesigned section headers', async ({ page }) => {
    await expect(page.locator('text=Blueprint Definition').first()).toBeVisible();
    await expect(page.locator('text=Trigger & Scope').first()).toBeVisible();
  });

  test('fills in blueprint name and publishes successfully', async ({ page }) => {
    await page.fill('[label="Blueprint Name"]', 'E2E Test Workflow');

    // Accept the published notification (the notify hook fires a snackbar)
    page.once('dialog', (d) => d.accept());

    await page.click('button:has-text("Publish Blueprint")');

    // Should show success toast or navigate away
    const successMsg = page.locator('text=published successfully');
    await expect(successMsg).toBeVisible({ timeout: 8_000 });
  });

  test('shows validation error when approval step has no assignee', async ({ page }) => {
    // Drop an approval node
    const approvalItem = page.locator('text=Approval').first();
    const canvas       = page.locator('.react-flow__pane');
    await approvalItem.dragTo(canvas, {
      sourcePosition: { x: 5, y: 5 },
      targetPosition: { x: 400, y: 300 },
    });

    await page.fill('[label="Blueprint Name"]', 'Invalid Workflow');
    await page.click('button:has-text("Publish Blueprint")');

    await expect(
      page.locator('text=must have an Assignee')
    ).toBeVisible({ timeout: 5_000 });
  });
});

test.describe('Workflow Designer — node configuration', () => {
  test.beforeEach(async ({ page }) => {
    await loginAsAdmin(page);
    await openWorkflowDesigner(page);
  });

  test('configures a Delay node', async ({ page }) => {
    const delayItem = page.locator('text=Delay / Wait').first();
    const canvas    = page.locator('.react-flow__pane');
    await delayItem.dragTo(canvas, {
      sourcePosition: { x: 5, y: 5 },
      targetPosition: { x: 400, y: 300 },
    });

    // The delay info hint should be visible
    await expect(
      page.locator('text=Workflow pauses here')
    ).toBeVisible({ timeout: 5_000 });
  });

  test('configures a Webhook node URL', async ({ page }) => {
    const webhookItem = page.locator('text=Webhook').first();
    const canvas      = page.locator('.react-flow__pane');
    await webhookItem.dragTo(canvas, {
      sourcePosition: { x: 5, y: 5 },
      targetPosition: { x: 400, y: 350 },
    });

    const urlInput = page.locator('[label="nodes.webhook.url"]').first();
    await urlInput.fill('https://hooks.example.com/test');
    await expect(urlInput).toHaveValue('https://hooks.example.com/test');
  });
});

