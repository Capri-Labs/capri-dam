# CLAUDE.md

Context and operating rules for AI coding assistants (Claude, GitHub Copilot,
Cursor, etc.) working in the Capri DAM repository. Read this **before** making
changes. For broader, tool-agnostic agent guidance see [`AGENTS.md`](AGENTS.md).

---

## What this project is

**Capri DAM** is a headless Digital Asset Management platform built as a
**hybrid Rails monolith**: server-rendered HTML shells (Hotwire/Turbo) with
mounted **React 19 islands**, exposing both a **REST API** (`/api/v1/**`) and a
**GraphQL API** (`/graphql`). Background processing runs on **Sidekiq**. Search
uses **PostgreSQL + pgvector** for semantic similarity.

---

## Tech stack (authoritative — do not assume otherwise)

| Layer | Technology |
|-------|-----------|
| Language | Ruby `4.0.3` (see `.ruby-version`) |
| Framework | Rails `~> 8.1` |
| Node | `22.16.0` (see `.node-version`), engines `>=20` |
| Frontend | React `19`, **MUI v9**, `@xyflow/react`, TipTap, Recharts |
| Bundler (JS) | esbuild (`yarn build`) |
| DB | PostgreSQL 14 + **pgvector** (via `neighbor` gem) |
| Jobs | Sidekiq + `sidekiq-throttled`, Redis |
| Auth | Devise, Doorkeeper (OAuth2), OmniAuth Keycloak (SSO) |
| Storage | ActiveStorage → local / S3 / GCS / Azure Blob + CDN |
| API docs | rswag (OpenAPI), SpectaQL (GraphQL) |
| Tests | RSpec, Jest + Testing Library, Playwright |
| Lint/Sec | rubocop-rails-omakase, Brakeman, bundler-audit |
| License | Apache 2.0 |

> Note: MUI is on **v9** in `package.json`. Prefer the modern `slotProps` API
> over deprecated prop aliases (`PaperProps`, `InputProps`, …).

---

## Golden rules

1. **Never break CI.** Every change must keep RuboCop, Brakeman, RSpec, Jest,
   and Playwright green. Run the relevant gate locally before claiming done.
2. **Tests are mandatory.** New behaviour → new/updated specs. Bug fix →
   regression test that fails before, passes after.
3. **Do not edit existing migrations.** Add a new, reversible migration and
   re-dump `db/schema.rb`.
4. **No hard-coded user-facing strings.** Use i18n (`useTranslation` /
   `t('key')`); add the key to `en.json` first, then other locales.
5. **API changes require doc regeneration.** Run `make api-docs` after touching
   `app/controllers/api/v1/**` or `app/graphql/**`.
6. **Respect Zeitwerk.** File path must mirror the Ruby namespace exactly.
7. **Service objects over fat models/controllers.** Put business logic in
   `app/services/`.

---

## Prohibited patterns

- ❌ `console.log` (or `puts`/`p` debugging) left in committed code.
- ❌ Editing a previously-shipped migration file.
- ❌ Adding a `null: false` column without a `default:`.
- ❌ Storing non-canonical timezone strings — use IANA values like
  `"Etc/UTC"`, never `"UTC"`. (Timezone is **server-managed** and is *not*
  exposed in the profile API/UI.)
- ❌ Bypassing RuboCop with blanket `# rubocop:disable` for whole files.
- ❌ Introducing a new HTTP client when `faraday` is already pinned (CVE floors
  in `Gemfile`).
- ❌ Committing secrets — credentials are encrypted (`config/credentials.yml.enc`).

---

## Common commands

```bash
# Run everything for dev (Rails + esbuild watch + Sidekiq)
bin/dev                 # or: make dev

# Backend
make test               # full RSpec suite (prepares test DB first)
bundle exec rspec spec/requests/profile_spec.rb
bundle exec rubocop
bundle exec brakeman -q

# Frontend
yarn test               # Jest
yarn test --watch
yarn playwright test    # E2E (server must be running)

# Docs (run after API/GraphQL changes)
make api-docs           # regenerate REST + GraphQL docs
make check-api-specs    # verify every api/v1 controller has a spec
```

---

## Where things live

| Path | Contents |
|------|----------|
| `app/controllers/api/v1/` | REST endpoints (each needs a request spec + Swagger) |
| `app/graphql/` | GraphQL types, queries, mutations |
| `app/services/` | Business logic / service objects |
| `app/javascript/components/<Domain>/` | React components |
| `app/javascript/i18n/locales/` | Frontend translation bundles |
| `config/locales/` | Server-side (flash/API error) translations |
| `app/workers/` & `app/jobs/` | Sidekiq workers / Active Jobs |
| `db/migrate/` | Migrations (never edit shipped ones) |
| `docs/architecture/` | arc42 documentation (source of truth) |
| `spec/` | RSpec: `requests/`, `models/`, `services/`, `system/`, `e2e/` |

---

## Definition of done

Before reporting a task complete, confirm:

- [ ] Code compiles / boots and the feature works.
- [ ] Specs added or updated; relevant suite passes.
- [ ] `bundle exec rubocop` clean on changed files.
- [ ] No `console.log` / stray debug output.
- [ ] i18n keys added for any new UI strings.
- [ ] Migration is reversible and `db/schema.rb` re-dumped (if schema changed).
- [ ] API docs regenerated (if endpoints changed).
- [ ] Docs updated (if behaviour/architecture changed).

---

For deeper conventions, contributor setup, and the testing matrix, see
[`CONTRIBUTING.md`](CONTRIBUTING.md). For the architecture, see
[`ARCHITECTURE.md`](ARCHITECTURE.md) and [`docs/architecture/`](docs/architecture/).

