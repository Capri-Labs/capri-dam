# Contributing to Capri DAM

Thank you for investing your time in contributing to Capri DAM!  
Read this guide before opening an issue, pull request, or discussion.

---

## Table of contents

- [Code of Conduct](#code-of-conduct)
- [Getting started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [Local development setup](#local-development-setup)
  - [Running the application](#running-the-application)
- [How to contribute](#how-to-contribute)
  - [Bug reports](#bug-reports)
  - [Feature requests](#feature-requests)
  - [Pull requests](#pull-requests)
- [Development guidelines](#development-guidelines)
  - [Branch naming](#branch-naming)
  - [Commit messages](#commit-messages)
  - [Ruby / Rails style](#ruby--rails-style)
  - [JavaScript / React style](#javascript--react-style)
  - [Database migrations](#database-migrations)
  - [i18n](#i18n)
- [Testing](#testing)
  - [Backend (RSpec)](#backend-rspec)
  - [Frontend (Jest)](#frontend-jest)
  - [End-to-end (Playwright)](#end-to-end-playwright)
  - [CI gates](#ci-gates)
- [Architecture](#architecture)
- [Security disclosures](#security-disclosures)
- [License](#license)

---

## Code of Conduct

This project follows the [Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md).  
By participating you agree to abide by its terms.

---

## Getting started

### Prerequisites

| Tool | Minimum version | Notes |
|------|----------------|-------|
| Ruby | see `.ruby-version` | Managed via rbenv / asdf |
| Node.js | see `.node-version` | Managed via nvm / fnm / asdf |
| Yarn | 1.22.x | `npm install -g yarn` |
| PostgreSQL | 14 + **pgvector** extension | `pgvector/pgvector:pg14` image works |
| Redis | 6+ | Required for Sidekiq and Action Cable |
| ImageMagick | 7+ | Required for image variant processing |
| ExifTool | 12+ | Required for full EXIF/IPTC/XMP metadata extraction |
| Java (JRE) | 11+ | Required for PlantUML in doc generation |
| FFmpeg | 5+ | Optional but recommended — enables video transcoding/preview renditions. Feature-detected at runtime (`which ffmpeg`); without it, video assets upload fine but skip transcoded previews. `brew install ffmpeg` |
| LibreOffice | 7+ | Optional but recommended — enables headless conversion of Office documents (doc/docx/ppt/pptx/xls/xlsx/rtf) into previews via `soffice --convert-to pdf`. Feature-detected at runtime (`which soffice`); without it, Office documents upload fine but show no preview. `brew install --cask libreoffice` |

### Local development setup

```bash
# 1. Clone
git clone https://github.com/your-org/headless-dam.git
cd headless-dam

# 2. Install Ruby dependencies
bundle install

# 3. Install JS dependencies
yarn install

# 4. Copy and configure environment secrets
# (credentials are encrypted — ask a maintainer for the master key
#  or supply your own via RAILS_MASTER_KEY)

# 5. Bootstrap the database
bin/rails db:setup

# 6. Seed demo data (optional)
bin/rails db:seed
```

### Running the application

```bash
# All processes in one terminal (Rails + esbuild watch + Sidekiq)
bin/dev

# Or individually:
bin/rails server          # Rails on :3000
yarn build --watch        # esbuild in watch mode
bundle exec sidekiq       # Background workers
```

The application will be available at <http://localhost:3000>.

---

## How to contribute

### Bug reports

1. Search [existing issues](../../issues) first.
2. If not found, open a new issue and fill in the **Bug** template.
3. Include: steps to reproduce, expected vs actual behaviour, Rails/Node version,
   browser, and any relevant log output.

### Feature requests

1. Open a **Feature Request** issue describing the problem you are solving,
   not just the solution.
2. For large changes discuss the design first — a small RFC comment in the issue
   saves everyone time.

### Pull requests

1. Fork the repository and create a branch from `main`.
2. Follow the [branch naming](#branch-naming) convention.
3. Make your changes; add or update tests so CI stays green.
4. Update documentation if your change affects user-facing behaviour,
   the API, or the architecture.
5. Open a PR against `main` and fill in the PR template.
6. A maintainer will review within a few business days.

**PRs are squash-merged.** Your commit history inside the branch does not need to
be linear, but the PR title will become the merge commit message — write it
accordingly.

---

## Development guidelines

### Branch naming

```
<type>/<short-description>

feat/asset-tagging-ui
fix/group-slug-null-query
chore/bump-ruby-3-4
docs/update-architecture-adr
```

Types: `feat`, `fix`, `refactor`, `perf`, `test`, `docs`, `chore`, `ci`.

### Commit messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
feat(assets): add bulk-tag endpoint with rate limiting
fix(groups): exclude NULL slugs from "everyone" filter
docs(architecture): add ADR-009 impersonation decision
```

### Ruby / Rails style

- Style is enforced by **RuboCop** with the `rubocop-rails-omakase` profile.  
  Run `bundle exec rubocop` before pushing; CI will reject offending code.
- Prefer service objects in `app/services/` over fat models or controllers.
- Follow **Zeitwerk naming**: the directory path must mirror the Ruby namespace exactly.  
  `app/services/ingestion_adapters/base.rb` → `IngestionAdapters::Base`.
- Every new public endpoint needs a **Swagger annotation** (`spec/swagger_helper.rb`).
- Every model change needs a **migration**; never alter existing migration files.

### JavaScript / React style

- ESLint + Prettier enforce style automatically.
- Components live in `app/javascript/components/<Domain>/`.
- Use **MUI v9** component APIs (no legacy prop aliases such as `PaperProps` —
  use `slotProps={{ paper: … }}` instead).
- All user-visible strings **must** use `useTranslation()` from react-i18next.  
  Add the key to `app/javascript/i18n/locales/en.json` first, then the other
  locale files.
- Do **not** call `console.log` in production code.

### Database migrations

- Column defaults must use IANA-canonical values where applicable
  (e.g. `"Etc/UTC"` not `"UTC"`).
- Every `add_column` with `null: false` must supply a `default:`.
- Migrations must be reversible (implement `up`/`down` or use `change`).
- Run `bundle exec rails db:schema:dump` after migrating and commit
  `db/schema.rb` with your PR.

### i18n

- UI labels, buttons, and error messages: static JSON bundles under
  `app/javascript/i18n/locales/`.
- Server-side flash / API error messages: Rails locale files under
  `config/locales/`.
- Never hard-code English strings in JSX; always use `t('key')`.

---

## Testing

### Backend (RSpec)

```bash
# All specs
bundle exec rspec

# Single file
bundle exec rspec spec/requests/profile_spec.rb

# With coverage
COVERAGE=true bundle exec rspec
```

### Frontend (Jest)

```bash
# All unit tests
yarn test

# Watch mode
yarn test --watch

# Specific file
yarn test spec/javascript/i18n/i18n.test.js
```

### End-to-end (Playwright)

```bash
# Install browsers once
yarn playwright install --with-deps chromium

# Start Rails in test mode first
RAILS_ENV=test bundle exec rails server -p 3000 &

# Run all E2E specs
yarn playwright test

# Run with UI
yarn playwright test --ui
```

### CI gates

All of the following must be green before a PR can be merged:

| Gate | Command |
|------|---------|
| RuboCop | `bundle exec rubocop` |
| Brakeman | `bundle exec brakeman -q` |
| RSpec | `COVERAGE=true bundle exec rspec` |
| Jest | `yarn test --ci` |
| System tests | `bundle exec rspec spec/system/` |
| Playwright E2E | `yarn playwright test` |
| Docker build | `docker build .` |

---

## Architecture

See [`ARCHITECTURE.md`](ARCHITECTURE.md) for a summary and links to the full
arc42 documentation set in [`docs/architecture/`](docs/architecture/).

---

## Security disclosures

**Do not open a public issue for security vulnerabilities.**

Email `security@capri-dam.dev` (or use the GitHub private vulnerability
reporting feature) with a description of the issue, impact, and reproduction
steps. We aim to acknowledge reports within 48 hours and provide a fix within
90 days.

---

## License

By contributing to Capri DAM you agree that your contributions will be licensed
under the [Apache License 2.0](LICENSE).
