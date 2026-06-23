// Babel config shared by Jest (unit tests) and the Istanbul-instrumented
// build used for Playwright E2E frontend coverage.
//
// esbuild handles the production bundle (see package.json `build`), so this
// config only affects test tooling.
module.exports = {
  presets: [
    ['@babel/preset-env', { targets: { node: 'current' } }],
    ['@babel/preset-react', { runtime: 'automatic' }]
  ],
  env: {
    // `BABEL_ENV=istanbul yarn build:e2e` instruments the bundle so Playwright
    // can collect window.__coverage__ for Istanbul/nyc reporting.
    istanbul: {
      plugins: ['istanbul']
    }
  }
};

