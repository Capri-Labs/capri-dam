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
  await page.goto(`${BASE}/users/sign_in`);
  // The test suite uses the seeded admin credentials.
  // Login is handled by the React SPA — use autocomplete selectors.
  await page.waitForSelector('input[autocomplete="email"]', { timeout: 15_000 });
  await page.fill('input[autocomplete="email"]', process.env.ADMIN_EMAIL || 'admin@admin.com');
  await page.fill('input[autocomplete="current-password"]', process.env.ADMIN_PASSWORD || 'AdminUser');

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

async function openWorkflowDesigner(page) {
  // There is no dedicated /workflows/new route — WorkflowContainer.jsx renders
  // the designer via client-side state when the "Create New Workflow" button
  // is clicked on the /workflows list page (see WorkflowContainer.jsx).
  await page.goto(`${BASE}/workflows`);
  await page.waitForLoadState('networkidle');
  await page.getByRole('button', { name: /create new workflow/i }).click();
  await page.waitForSelector('[data-testid="workflow-canvas"], .react-flow', { timeout: 15_000 });
}

// NodePalette.jsx implements native HTML5 drag-and-drop (draggable + onDragStart
// with dataTransfer.setData('application/reactflow', nodeType)), and
// WorkflowCanvas.jsx's onDrop reads it back via dataTransfer.getData(). Playwright's
// locator.dragTo() only simulates mouse events, which Chromium's native DnD does
// NOT reliably translate into dragstart/dragover/drop with populated dataTransfer
// for items that require scrolling within the palette's overflow container — this
// caused a real, pre-existing bug where the wrong node (or none) got dropped.
// The Playwright-recommended fix for HTML5 DnD is to dispatch the drag events
// directly with a real DataTransfer object, bypassing mouse-position simulation
// entirely (see https://playwright.dev/docs/input#drag-and-drop-with-html5).
async function dragPaletteItemToCanvas(page, itemText) {
  // Use an exact match so a substring match doesn't accidentally grab a
  // category header instead of the tool item (e.g. "Approval" is also a
  // substring of the "Approval & Review" category label, which sits earlier
  // in the DOM and would otherwise be picked up by .first()).
  const source = page.getByText(itemText, { exact: true }).first();
  await source.scrollIntoViewIfNeeded();
  const canvas = page.locator('.react-flow__pane');
  const box = await canvas.boundingBox();
  // Drop roughly in the middle of the canvas — WorkflowCanvas.jsx's onDrop
  // uses event.clientX/clientY (via screenToFlowPosition) to place the new
  // node, and dispatchEvent doesn't set them by default (defaulting to
  // 0,0), which placed nodes off-screen/behind other UI and made later
  // interactions (e.g. clicking its fields) flaky.
  const clientX = box ? box.x + box.width / 2 : 400;
  const clientY = box ? box.y + box.height / 2 : 300;
  const dataTransfer = await page.evaluateHandle(() => new DataTransfer());
  await source.dispatchEvent('dragstart', { dataTransfer });
  await canvas.dispatchEvent('dragover', { dataTransfer, clientX, clientY });
  await canvas.dispatchEvent('drop', { dataTransfer, clientX, clientY });
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
    await dragPaletteItemToCanvas(page, 'Send Email');

    // The dropped node header should appear
    await expect(page.locator('text=Send Email').nth(1)).toBeVisible({ timeout: 5_000 });
  });

  test('drops a Condition node and shows TRUE/FALSE branch labels', async ({ page }) => {
    await dragPaletteItemToCanvas(page, 'Condition Branch');

    await expect(page.locator('text=TRUE')).toBeVisible({ timeout: 5_000 });
    await expect(page.locator('text=FALSE')).toBeVisible({ timeout: 5_000 });
  });

  test('drops a Switch node and shows the DEFAULT branch label', async ({ page }) => {
    await dragPaletteItemToCanvas(page, 'Switch / Multi-branch');

    // The switch node always renders a default output branch chip. Use an exact
    // match so it doesn't collide with the "Default Output Label" field label.
    await expect(page.getByText('DEFAULT', { exact: true })).toBeVisible({ timeout: 5_000 });
    // The switch field input (t('nodes.switch.field') → "Switch Field") is present.
    await expect(page.getByLabel('Switch Field').first()).toBeVisible({ timeout: 5_000 });
  });

  test('adds cases to a Switch node and renders labelled branches', async ({ page }) => {
    await dragPaletteItemToCanvas(page, 'Switch / Multi-branch');

    // Ensure the node actually mounted before interacting (drag can be async).
    await expect(page.getByLabel('Switch Field').first()).toBeVisible({ timeout: 5_000 });

    // The dropped node can extend under the ReactFlow minimap (bottom-right),
    // which sits on top and would receive a real mouse click. dispatchEvent
    // delivers the click straight to the button, bypassing hit-testing.
    await page.getByRole('button', { name: 'Add Case' }).dispatchEvent('click');

    // A new case row appears with its own "Output Label" field.
    await expect(page.getByText('Case 1', { exact: true })).toBeVisible({ timeout: 5_000 });
    const labelInput = page.getByLabel('Output Label').first();
    await labelInput.fill('images');
    // The branch footer chip mirrors the case handle id (the output label).
    await expect(page.getByText('images', { exact: true }).first()).toBeVisible({ timeout: 5_000 });
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
    // "Active workflows must have at least one approval step" — drop an
    // Approval node and assign it (users/groups are preloaded via props on
    // the node, so the Autocomplete options are available immediately).
    await dragPaletteItemToCanvas(page, 'Approval');
    await page.getByLabel('Search user…').click();
    await page.getByRole('option').first().click();

    await page.getByLabel('Blueprint Name').fill('E2E Test Workflow');

    // Accept the published notification (the notify hook fires a snackbar)
    page.once('dialog', (d) => d.accept());

    await page.click('button:has-text("Publish Blueprint")');

    // Should show success toast or navigate away
    const successMsg = page.locator('text=published successfully');
    await expect(successMsg).toBeVisible({ timeout: 8_000 });
  });

  test('shows validation error when approval step has no assignee', async ({ page }) => {
    // Drop an approval node
    await dragPaletteItemToCanvas(page, 'Approval');

    await page.getByLabel('Blueprint Name').fill('Invalid Workflow');
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
    await dragPaletteItemToCanvas(page, 'Delay / Wait');

    // The delay info hint should be visible
    await expect(
      page.locator('text=Workflow pauses here')
    ).toBeVisible({ timeout: 5_000 });
  });

  test('configures a Webhook node URL', async ({ page }) => {
    await dragPaletteItemToCanvas(page, 'Webhook');

    // "Endpoint URL" is the rendered label for t('nodes.webhook.url') (see
    // WebhookNode.jsx / en.json), not the raw translation key.
    const urlInput = page.getByLabel('Endpoint URL').first();
    await urlInput.fill('https://hooks.example.com/test');
    await expect(urlInput).toHaveValue('https://hooks.example.com/test');
  });
});

