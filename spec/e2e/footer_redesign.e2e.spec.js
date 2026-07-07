// Global Footer E2E — covers the redesigned Footer.jsx:
//
//  1. Footer renders on an authenticated page with the product logo, tagline,
//     and brand accent stripe (visual redesign to match the product logo).
//  2. Product / Resources / Legal & Security link columns render with the
//     correct hrefs (Product links point at real in-app routes: dashboard,
//     search, workflows, duplicate manager).
//  3. Bottom bar shows copyright (with the current year) and the
//     "All systems operational" status indicator.
//
// Runs against a live Rails server (set E2E_BASE_URL, E2E_EMAIL, E2E_PASSWORD).

const { test, expect } = require('./fixtures');

const EMAIL    = process.env.E2E_EMAIL    || 'admin@admin.com';
const PASSWORD = process.env.E2E_PASSWORD || 'AdminUser';

async function login(page) {
    await page.goto('/users/sign_in');
    await page.waitForSelector('input[autocomplete="email"]', { timeout: 15_000 });
    await page.fill('input[autocomplete="email"]', EMAIL);
    await page.fill('input[autocomplete="current-password"]', PASSWORD);

    const [response] = await Promise.all([
        page.waitForResponse((res) => res.url().includes('/users/sign_in.json'), { timeout: 15_000 }),
        page.click('button[type="submit"], input[type="submit"]'),
    ]);
    if (!response.ok()) throw new Error(`login failed with status ${response.status()}`);

    await page.waitForURL(/^https?:\/\/[^/]+\/?(\?.*)?$/, { timeout: 15_000 });
    await page.waitForLoadState('networkidle');
}

test.describe('Global Footer redesign', () => {
    test.beforeEach(async ({ page }) => {
        await login(page);
        await page.goto('/dashboard');
        await page.waitForLoadState('networkidle');
    });

    test('renders the product logo, tagline, and brand accent stripe', async ({ page }) => {
        const footer = page.getByTestId('app-footer');
        await expect(footer).toBeVisible();

        await expect(footer.getByAltText('Capri DAM')).toBeVisible();
        await expect(footer.getByText(/intelligent operating system/i)).toBeVisible();

        // Brand accent stripe (::before pseudo-element) — assert the footer
        // element itself is positioned to host it (visual regression is out
        // of scope for Playwright, so we assert the DOM anchor instead).
        await expect(footer).toHaveCSS('position', 'relative');
    });

    test('Product, Resources, and Legal & Security columns link to the correct URLs', async ({ page }) => {
        const footer = page.getByTestId('app-footer');

        await expect(footer.getByText('Product')).toBeVisible();
        await expect(footer.getByRole('link', { name: 'Dashboard' })).toHaveAttribute('href', '/dashboard');
        await expect(footer.getByRole('link', { name: 'Semantic Search' })).toHaveAttribute('href', '/search');
        await expect(footer.getByRole('link', { name: 'Workflows' })).toHaveAttribute('href', '/workflows');
        await expect(footer.getByRole('link', { name: 'Duplicate Manager' })).toHaveAttribute('href', '/duplicates');

        await expect(footer.getByText('Resources')).toBeVisible();
        await expect(footer.getByRole('link', { name: 'API Documentation' })).toHaveAttribute('href', '/api/rest');
        await expect(footer.getByRole('link', { name: 'GraphQL API' })).toHaveAttribute('href', '/api/graphql');
        await expect(footer.getByRole('link', { name: 'OpenAPI Reference' })).toHaveAttribute('href', '/api-docs');

        await expect(footer.getByText('Legal & Security')).toBeVisible();
        await expect(footer.getByRole('link', { name: 'Privacy Policy' })).toHaveAttribute('href', '/privacy');
        await expect(footer.getByRole('link', { name: 'Terms of Service' })).toHaveAttribute('href', '/terms');
        await expect(footer.getByRole('link', { name: 'GDPR Compliance' })).toHaveAttribute('href', '/compliance');
    });

    test('bottom bar shows the current-year copyright and system status', async ({ page }) => {
        const footer = page.getByTestId('app-footer');
        const currentYear = new Date().getFullYear().toString();

        await expect(footer.getByText(new RegExp(`${currentYear}.*Capri DAM`))).toBeVisible();
        await expect(footer.getByText('All systems operational')).toBeVisible();
        await expect(footer.getByText(/v1\.0\.0-alpha/)).toBeVisible();
    });

    test('the "Dashboard" Product link navigates to the dashboard', async ({ page }) => {
        // Navigate elsewhere first so the click is a meaningful assertion.
        await page.goto('/search');
        await page.waitForLoadState('networkidle');

        await page.getByTestId('app-footer').getByRole('link', { name: 'Dashboard' }).click();
        await page.waitForURL(/\/dashboard$/, { timeout: 15_000 });
    });
});
