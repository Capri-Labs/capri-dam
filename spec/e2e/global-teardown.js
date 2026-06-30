// Playwright globalTeardown — runs once after all tests complete.
// Generates the monocart Istanbul coverage report from data collected
// per-test in spec/e2e/fixtures.js. Calling generate() here (instead of
// inside the per-test fixture) means the summary table is printed once,
// not once per test.

const MCR = require('monocart-coverage-reports');

const coverageOptions = {
  name: 'Capri DAM — Frontend E2E (Istanbul)',
  outputDir: './coverage-frontend/e2e',
  reports: ['html', 'lcovonly', 'console-summary'],
  entryFilter: {
    '**/assets/**': true,
    '**/node_modules/**': false
  },
  sourceFilter: {
    '**/app/javascript/**': true
  }
};

module.exports = async function globalTeardown() {
  const mcr = MCR(coverageOptions);
  await mcr.generate();
};
