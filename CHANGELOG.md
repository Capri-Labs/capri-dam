# Changelog

All notable changes to Capri DAM are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `Users::OmniauthCallbacksController` — was missing entirely; Keycloak SSO
  callbacks now reach `User.from_omniauth` and sign the user in correctly.
- `spec/requests/omniauth_callbacks_spec.rb` — full request-spec coverage of
  the SSO callback: new user, returning user, name fallback, username collision,
  deactivated user, and OmniAuth failure cases.
- Root-level project documentation: `CODE_OF_CONDUCT.md`, `RELEASING.md`,
  `CLAUDE.md`, `AGENTS.md`, `SECURITY.md`, `CHANGELOG.md`.
- `.editorconfig` and `.pre-commit-config.yaml` for consistent formatting and
  local quality gates.
- GitHub issue/PR templates (`bug_report.yml`, `feature_request.yml`) and
  `CODEOWNERS`.

### Changed
- `config/routes.rb` — `devise_for :users` now registers
  `omniauth_callbacks: "users/omniauth_callbacks"` so Keycloak callbacks route
  to the correct controller.
- `User.from_omniauth` — new users now have `first_name`, `last_name`, and
  `avatar_url` populated on **creation** (not only on re-login). Username
  uniqueness is now guarded: `jane_sso`, `jane_sso_2`, `jane_sso_3`, …
- `spec/models/user_spec.rb` — expanded `from_omniauth` coverage: first_name/
  last_name/avatar_url on creation, name fallback, username collision handling,
  email uniqueness constraint edge case.
- `spec/requests/sessions_spec.rb` — added `force_password_update` flow,
  deactivated user, unknown email, and mismatched-password cases.
- `docs/architecture/src/08_concepts.adoc` — replaced stale Prisma/Liquibase/
  Fastly/Vitest/Supertest references with the real Rails stack; added a
  PlantUML Keycloak OIDC sequence diagram and a security-layer table.
- `README.md` rewritten to match the current `Makefile`, `Gemfile`, and
  `package.json` (Rails 8.1, MUI v9, Node 22.16.0, full make-target reference).
- `ARCHITECTURE.md` reduced to a pointer to the arc42 set in `docs/architecture/`.
- `CONTRIBUTING.md` rewritten; MUI references updated from v6 to **v9**.
- `LICENSE` changed from MIT to **Apache 2.0**.
- `.node-version` bumped to `22.16.0`.

### Fixed
- **Keycloak SSO callback was unreachable** — missing controller and route
  meant every SSO login attempt resulted in
  `AbstractController::ActionNotFound`. Now fixed.
- `User.from_omniauth` — SSO users no longer had `first_name`, `last_name`,
  `avatar_url` set at account creation; they were only synced on subsequent
  logins. Now set on initial provision.
- `User.from_omniauth` — colliding SSO usernames (e.g. two `john@*` users)
  would raise `ActiveRecord::RecordNotUnique`; now resolved with counter suffix.
- Missing `devise.failure.account_deactivated` i18n key — `inactive_message`
  returned the symbol `:account_deactivated` but no locale string existed for
  it; added to `config/locales/devise.en.yml`.
- `PATCH /profile/preferences` no longer rejects the default timezone value.
  Timezone is now treated as a server-managed field and removed from the public
  profile API surface (model validation, permitted params, serializer, GraphQL
  type). Existing `'UTC'` rows normalised to the IANA-canonical `'Etc/UTC'`.

[Unreleased]: https://github.com/your-org/headless-dam/compare/main...HEAD

