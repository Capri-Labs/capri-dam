# Testing & Coverage Guide

This project measures coverage across **four** layers. All commands are exposed
through the `Makefile` (run `make help` to list them).

| Layer | Tool | Command | Report |
|-------|------|---------|--------|
| Backend unit + integration | RSpec + **SimpleCov** | `make coverage-backend` | `coverage/backend/index.html` (+ `coverage.xml` Cobertura) |
| Frontend unit + component | Jest + **Istanbul** | `make coverage-frontend` | `coverage-frontend/unit/index.html` |
| Backend E2E (runtime) | **Coverband** | `make e2e-backend` | `/admin/coverband` (admin-only dashboard) |
| Frontend E2E | Playwright + **Istanbul** (monocart) | `make e2e-frontend` | `coverage-frontend/e2e/index.html` |

## Backend coverage (RSpec + SimpleCov)

```bash
make coverage-backend          # full suite with coverage
# or directly:
COVERAGE=true bundle exec rspec
```

- SimpleCov is configured at the top of `spec/spec_helper.rb`.
- Set `COVERAGE=false` for a fast run with no instrumentation.
- Enforce a floor in CI: `COVERAGE_MIN=70 bundle exec rspec`.
- Output: HTML at `coverage/backend/index.html`, Cobertura XML at
  `coverage/backend/coverage.xml`.

Spec layout:

```
spec/models/      # unit specs (Asset, Folder, Notification, MetadataExport, MetadataImport, ...)
spec/services/    # service-object unit specs (CSV generator / processor)
spec/workers/     # Sidekiq worker integration specs
spec/requests/    # API request/integration specs
spec/system/      # backend E2E feature specs (Capybara, rack_test driver)
```

### rswag / OpenAPI doc specs (excluded by default)

The `spec/requests/**` files that `require 'swagger_helper'` and call `run_test!`
exist mainly to **generate the OpenAPI docs** (`make swagger-docs`). Most are
scaffolds without `let(:Authorization)` or path params, so they are **auto-tagged
`:api_doc` and excluded from the default `make test` / `make coverage-backend`
run** (see `spec/support/api_doc.rb`). This keeps the everyday suite green.

Run them explicitly (they authenticate as an admin automatically, but many are
incomplete and will report data/assertion failures until finished):

```bash
make test-api-docs            # RUN_API_DOCS=1 bundle exec rspec spec/requests
```

## Frontend coverage (Jest + Istanbul)

```bash
make coverage-frontend         # jest --coverage
# or:
yarn jest --coverage
yarn jest --watch              # TDD loop
```

- Config lives under the `jest` key in `package.json`; global setup in
  `spec/javascript/setup.js`.
- Tests live in `spec/javascript/**` and run in a `jsdom` environment with
  `@testing-library/react`.
- Output: `coverage-frontend/unit/index.html` (+ Cobertura XML).

## Backend E2E coverage (Coverband)

Coverband records which Ruby lines actually execute while the app serves **real
traffic** (manual click-throughs or the Playwright E2E run).

```bash
# 1. Start Redis + the app
make dev

# 2. Exercise the app (e.g. run the frontend E2E suite, or click around)
make e2e-frontend

# 3. Summarise / view
make e2e-backend                       # prints a line-coverage summary
#   open http://localhost:3000/admin/coverband   (admin login)
bundle exec rake coverband:clear       # reset collected data
```

- Config: `config/coverband.rb` (Redis store, falls back to a file store when
  Redis is down). Loaded only in `:development` / `:production`.

## Frontend E2E coverage (Playwright + Istanbul)

```bash
make playwright-install        # one-time: install browser binaries
make dev                       # app must be running (E2E_BASE_URL, default :3000)
make e2e-frontend              # runs Playwright, emits Istanbul report
```

- Config: `playwright.config.js`; tests in `spec/e2e/*.e2e.spec.js`.
- V8 coverage is collected per page and converted to an **Istanbul** HTML/lcov
  report via `monocart-coverage-reports` (`spec/e2e/fixtures.js`).
- Login is parameterised via `E2E_EMAIL` / `E2E_PASSWORD`.
- Output: `coverage-frontend/e2e/index.html`.

## Run everything

```bash
make coverage     # backend + frontend unit/integration coverage
make e2e          # backend + frontend E2E coverage (server must be running)
make test-all     # the entire matrix
```

