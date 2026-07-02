# Capri DAM (Digital Asset Management)

A modern, headless Digital Asset Management platform built as a **hybrid Rails
monolith**: server-rendered HTML shells (Hotwire/Turbo) with mounted **React 19
islands**, exposing both a **REST API** (`/api/v1/**`) and a **GraphQL API**
(`/graphql`). Background processing runs on **Sidekiq**, and semantic search is
powered by **PostgreSQL + pgvector**.

<!-- CI/CD -->
[![CI](https://github.com/Capri-Labs/capri-dam/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/Capri-Labs/capri-dam/actions/workflows/ci.yml)
[![Integration & Contract Tests](https://github.com/Capri-Labs/capri-dam/actions/workflows/integration.yml/badge.svg?branch=master)](https://github.com/Capri-Labs/capri-dam/actions/workflows/integration.yml)
[![E2E Tests](https://github.com/Capri-Labs/capri-dam/actions/workflows/e2e.yml/badge.svg?branch=master)](https://github.com/Capri-Labs/capri-dam/actions/workflows/e2e.yml)
[![SAST & Security](https://github.com/Capri-Labs/capri-dam/actions/workflows/sast.yml/badge.svg?branch=master)](https://github.com/Capri-Labs/capri-dam/actions/workflows/sast.yml)
[![Docker](https://github.com/Capri-Labs/capri-dam/actions/workflows/docker.yml/badge.svg?branch=master)](https://github.com/Capri-Labs/capri-dam/actions/workflows/docker.yml)

<!-- Code quality -->
[![Ruby Style: rubocop-rails-omakase](https://img.shields.io/badge/code%20style-rubocop--rails--omakase-red.svg)](https://github.com/rails/rubocop-rails-omakase)
[![Security: Brakeman](https://img.shields.io/badge/security-brakeman-orange.svg)](https://brakemanscanner.org)
[![JS Style: ESLint](https://img.shields.io/badge/code%20style-ESLint-4B32C3.svg)](https://eslint.org)

<!-- Stack -->
[![Ruby](https://img.shields.io/badge/Ruby-4.0.3-CC342D.svg?logo=ruby&logoColor=white)](https://www.ruby-lang.org)
[![Rails](https://img.shields.io/badge/Rails-8.1-CC0000.svg?logo=rubyonrails&logoColor=white)](https://rubyonrails.org)
[![React](https://img.shields.io/badge/React-19-61DAFB.svg?logo=react&logoColor=black)](https://react.dev)
[![Node](https://img.shields.io/badge/Node.js-22.x-339933.svg?logo=node.js&logoColor=white)](https://nodejs.org)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-14%20%2B%20pgvector-4169E1.svg?logo=postgresql&logoColor=white)](https://www.postgresql.org)

<!-- Tests -->
[![RSpec](https://img.shields.io/badge/tests-RSpec-9B2335.svg)](https://rspec.info)
[![Jest](https://img.shields.io/badge/tests-Jest-C21325.svg?logo=jest&logoColor=white)](https://jestjs.io)
[![Playwright](https://img.shields.io/badge/e2e-Playwright-2EAD33.svg?logo=playwright&logoColor=white)](https://playwright.dev)

<!-- License -->
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

---

## 🛠 Tech Stack

| Layer | Technology |
|-------|-----------|
| Language | Ruby `4.0.3` (see `.ruby-version`) |
| Framework | Rails `~> 8.1` |
| Node | `22.16.0` (see `.node-version`), engines `>=20` |
| Frontend | React `19`, **MUI v9**, Emotion 11, `@xyflow/react`, TipTap, Recharts |
| JS bundler | esbuild (`yarn build`) |
| Database | PostgreSQL 14 + **pgvector** (via the `neighbor` gem) |
| Background jobs | Sidekiq + `sidekiq-throttled`, Redis |
| Auth | Devise, Doorkeeper (OAuth2), OmniAuth Keycloak (SSO) |
| Storage | ActiveStorage → local / S3 / GCS / Azure Blob + CDN |
| API docs | rswag (OpenAPI/Swagger), SpectaQL (GraphQL) |
| Tests | RSpec, Jest + Testing Library, Playwright |
| Lint / Security | rubocop-rails-omakase, Brakeman, bundler-audit |
| License | Apache 2.0 |

---

## 📋 Prerequisites

| Tool | Version | Notes |
|------|---------|-------|
| Ruby | `4.0.3` | see `.ruby-version` (managed via rbenv) |
| Node.js | `22.16.0` | see `.node-version` |
| Yarn | 1.22.x | classic |
| PostgreSQL | 14 + **pgvector** | `make bootstrap` installs `postgresql@14` |
| Redis | 6+ | required for Sidekiq & Action Cable |
| ImageMagick / exiv2 | latest | image variants & metadata extraction |
| ExifTool | 12+ | full EXIF/IPTC/XMP/Photoshop metadata extraction |

On macOS with Homebrew, `make bootstrap` installs these for you.

---

## 🚀 Getting Started

The project uses a `Makefile` to automate system dependencies and application
configuration. Follow these steps in order.

### 1. Initial system bootstrap

If you are setting up on a new machine, this installs the required system
libraries (Redis, rbenv, ruby-build, Node, Yarn, exiv2, pkg-config, and
PostgreSQL 14) and ensures Ruby `4.0.3` is active.

```bash
make bootstrap
# After this completes, restart your terminal or run `source ~/.zshrc`
# to activate the new Ruby environment.
```

### 2. Application setup

Installs all Ruby gems and JavaScript packages, creates and prepares the
database, seeds a default admin user, and initialises RSpec.

```bash
make setup
```

> Credentials are encrypted in `config/credentials.yml.enc`. Supply the
> `RAILS_MASTER_KEY` (or `config/master.key`) before running setup.

### 3. Launch the development environment

Starts the Rails server, the esbuild JS watcher, and Sidekiq workers together.

```bash
make dev          # or: bin/dev
```

The application is available at <http://localhost:3000>.

---

## 🧪 Testing

```bash
make test               # full backend RSpec suite (prepares test DB first)
make test-frontend      # Jest unit & component tests
make test-graphql       # GraphQL endpoint request specs
make playwright-install # install Playwright browsers (one-time)
yarn playwright test    # end-to-end tests (server must be running)
```

### Coverage

```bash
make coverage           # backend (SimpleCov) + frontend (Istanbul)
make coverage-backend   # → coverage/backend/index.html
make coverage-frontend  # → coverage-frontend/unit/index.html
make e2e                # frontend (Playwright) + backend (Coverband) E2E
```

---

## 📚 API Documentation

```bash
make api-docs           # regenerate BOTH REST (Swagger) and GraphQL (SpectaQL) docs
make swagger-docs       # REST only   → view at /api/rest
make graphql-docs       # GraphQL only → view at /api/graphql
make check-api-specs    # verify every api/v1 controller has a request spec
make check-graphql-docs # verify GraphQL SDL + HTML docs are present
```

A pre-commit hook (`make install-hooks`) runs RuboCop on staged Ruby and blocks
API/GraphQL changes that ship without regenerated docs.

---

## ✅ Quality Gates

| Concern | Command |
|---------|---------|
| Ruby style | `bundle exec rubocop` |
| Ruby security | `bundle exec brakeman -q` |
| Dependency CVEs | `bundle exec bundler-audit check --update` |
| Backend tests | `make test` |
| Frontend tests | `yarn test --ci` |
| E2E | `yarn playwright test` |

---

## 🔧 Available Make Targets

| Command | Description |
|---------|-------------|
| `make bootstrap` | Install system packages and Ruby `4.0.3` (macOS/Homebrew) |
| `make setup` | Install dependencies, create & prepare the database, seed data |
| `make dev` | Start the server, JS watcher, and Sidekiq workers |
| `make db-setup` | Create and migrate the PostgreSQL database |
| `make seed` | Populate the database with the default admin user |
| `make test` | Run the full backend RSpec suite |
| `make test-frontend` | Run the Jest unit & component tests |
| `make api-docs` | Regenerate REST + GraphQL documentation |
| `make install-hooks` | Install the pre-commit lint + stale-docs hook |
| `make clean` | Wipe temporary logs and compiled asset builds |
| `make help` | Display the full list of automation targets |

---

## 📖 Further Reading

- [`CONTRIBUTING.md`](CONTRIBUTING.md) — setup, style guides, and the testing matrix
- [`ARCHITECTURE.md`](ARCHITECTURE.md) — pointer to the full arc42 doc set in
  [`docs/architecture/`](docs/architecture/)
- [`CLAUDE.md`](CLAUDE.md) / [`AGENTS.md`](AGENTS.md) — operating rules for AI coding assistants
- [`RELEASING.md`](RELEASING.md) — release and deployment process
- [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md) — community standards

---

## 📄 License

Capri DAM is released under the [Apache License 2.0](LICENSE).
