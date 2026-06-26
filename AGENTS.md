# AGENTS.md

Tool-agnostic operating manual for AI agents working in the Capri DAM
repository. This complements [`CLAUDE.md`](CLAUDE.md) (assistant-specific
context) and [`CONTRIBUTING.md`](CONTRIBUTING.md) (human contributor guide).
If guidance ever conflicts, the order of precedence is:

> `AGENTS.md` (workflow) → `CLAUDE.md` (stack rules) → `CONTRIBUTING.md` (process)

---

## Operating principles

1. **Understand before editing.** Read the surrounding code and trace symbols to
   their definitions and usages. Do not guess at APIs or file locations.
2. **Make the smallest correct change.** Solve the actual request; avoid
   opportunistic refactors unless asked.
3. **Leave the tree greener.** Add tests, keep lint clean, update docs touched by
   your change.
4. **Be reversible.** Migrations, feature flags, and config changes must be safe
   to roll back.
5. **Never invent facts.** If a value (version, env var, path) is unknown, look
   it up in the repo rather than assuming.

---

## Standard workflow

```
1. Clarify the goal        → restate the task and acceptance criteria
2. Gather context          → read relevant files, specs, and docs
3. Plan                    → list the files to touch and the approach
4. Implement               → minimal, focused edits
5. Test                    → add/adjust specs; run the relevant suite
6. Self-review             → lint, security scan, docs, debug-output check
7. Summarise               → what changed, why, and how it was verified
```

---

## File organisation & naming

- **Zeitwerk**: the path under `app/` mirrors the Ruby namespace.
  `app/services/ingestion_adapters/base.rb` → `IngestionAdapters::Base`.
- **React components**: PascalCase files under
  `app/javascript/components/<Domain>/`.
- **Specs** mirror their subject:
  `app/services/foo/bar.rb` → `spec/services/foo/bar_spec.rb`.
- **REST controllers** in `app/controllers/api/v1/` each require a matching
  `spec/requests/api/v1/<name>_spec.rb` (enforced by `make check-api-specs`).

---

## Handling common change types

### Database migrations
- Generate a **new** migration; never edit a shipped one.
- Provide `default:` for any `null: false` column.
- Make it reversible (`change`, or explicit `up`/`down`).
- Use IANA-canonical values for defaults (e.g. `"Etc/UTC"`, not `"UTC"`).
- Re-dump and commit `db/schema.rb`.

### API endpoints (REST)
- Add the endpoint, a request spec, and a Swagger annotation.
- Regenerate docs: `make swagger-docs` (or `make api-docs`).

### GraphQL
- Update types/queries/mutations under `app/graphql/`.
- Regenerate the SDL + HTML docs: `make graphql-docs`.

### Frontend / UI strings
- Use `useTranslation()` from `react-i18next`; no literal English in JSX.
- Add the key to `app/javascript/i18n/locales/en.json` first, then the other
  locale files.
- Use **MUI v9** APIs — prefer `slotProps={{ … }}` over deprecated prop aliases.

### Background work
- Long-running or external I/O belongs in a Sidekiq worker (`app/workers/`),
  not inline in a request.

---

## Server-managed fields (do not expose)

Some columns exist for internal use only and must **not** be added to public
API responses, permitted params, serializers, or GraphQL types:

- **`user_preferences.timezone`** — used for internal timestamp display; it is
  managed server-side and intentionally absent from the profile UI/API. Do not
  reintroduce it into `ProfileController#preference_params`,
  `serialize_preference`, or `Types::UserPreferenceType`.

---

## Verification gates (run what's relevant)

| Concern | Command |
|---------|---------|
| Ruby style | `bundle exec rubocop` |
| Ruby security | `bundle exec brakeman -q` |
| Dependency CVEs | `bundle exec bundler-audit check --update` |
| Backend tests | `make test` |
| Frontend tests | `yarn test --ci` |
| E2E | `yarn playwright test` |
| API spec coverage | `make check-api-specs` |
| GraphQL docs present | `make check-graphql-docs` |

A pre-commit hook (`make install-hooks`) runs RuboCop on staged Ruby and blocks
API/GraphQL changes that ship without regenerated docs.

---

## Communication & output

- Reference files by path; quote only the lines that matter.
- When you finish, give a concise summary: **what** changed, **why**, and
  **how** you verified it.
- Surface risks, assumptions, and follow-ups explicitly.
- Do not claim a task is done until the relevant verification gate passes.

---

## Hard "do not" list

- Do not edit shipped migrations or commit a schema that drifts from migrations.
- Do not commit secrets; credentials are encrypted in
  `config/credentials.yml.enc`.
- Do not leave `console.log` / `puts` debug output in committed code.
- Do not hard-code user-facing strings (use i18n).
- Do not expose server-managed fields (see above).
- Do not add a new HTTP client; `faraday` is pinned with CVE floors in the
  `Gemfile`.
- Do not weaken CVE version floors in the `Gemfile`.

---

For setup, the full testing matrix, and contribution process, see
[`CONTRIBUTING.md`](CONTRIBUTING.md). For architecture, see
[`ARCHITECTURE.md`](ARCHITECTURE.md) and [`docs/architecture/`](docs/architecture/).

