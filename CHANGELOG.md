# Changelog

All notable changes to Capri DAM are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

#### Duplicate Manager — Background Repository Scan
- **`DuplicateRepositoryScanWorker`** — Sidekiq worker (queue: `duplicate_detection`,
  retries: 1) that performs a full-repository scan using a single PostgreSQL query:
  `GROUP BY checksum HAVING COUNT(DISTINCT asset_id) > 1`.
  **Version-awareness rule enforced**: multiple versions of the same asset sharing
  a checksum are intentionally **not** counted as duplicates — only two or more
  *different assets* with the same SHA-256 fingerprint create a `DuplicateGroup`.
- **Auto-trigger on enable**: the scan is enqueued automatically when an admin
  enables duplicate detection (`PATCH /api/v1/duplicate_manager_settings` with
  `enabled: true`), so all pre-existing repository assets are analysed immediately.
- **REST API additions** (`DuplicateManagerSettingsController`):
  - `GET  /api/v1/duplicate_manager_settings/scan_status` — live scan progress
    (status, processed/total, last_scan_at).
  - `POST /api/v1/duplicate_manager_settings/trigger_scan` — admin can manually
    kick off a full scan; returns 422 if a scan is already running/queued.
  - `GET/PATCH /api/v1/duplicate_manager_settings` now includes `scan_status`,
    `scan_progress`, and `last_scan_at` in every response.
- **GraphQL addition**:
  - `duplicateManagerScanStatus` query — returns `scan_status`, `scan_progress`,
    `last_scan_at` for dashboard integrations.
  - `triggerDuplicateScan` mutation — admin-only; queues the repository scan.
- **Scan status tracking** via the `Setting` model (keys:
  `duplicate_manager_scan_status`, `duplicate_manager_scan_progress`,
  `duplicate_manager_last_scan_at`).
- **Concurrency guard**: `DuplicateRepositoryScanWorker#perform` exits immediately
  when the status is already `"running"` — no overlapping scans.
- **Frontend updates** (`DuplicateManagerSettings.jsx`):
  - New **Repository Scan** card below the toggles showing status chip
    (idle / queued / running / completed / failed), animated progress bar
    during scan, last-scan timestamp, and a **"Run Full Scan"** button.
  - Auto-polls `GET /api/v1/duplicate_manager_settings/scan_status` every 3 s
    while a scan is active; polling clears automatically when idle.
  - When detection is enabled, an `autoQueued` toast informs the user.
- **i18n**: `duplicateManager.scan.*` keys added to all 9 locale files
  (en, de, fr, es, ja, ko, nl, pt, zh), including `versionNote` to explain
  the version-awareness rule to end users.
- **Specs added**:
  - `spec/workers/duplicate_repository_scan_worker_spec.rb` — 20 examples
    covering: detection disabled, already running, no duplicates, version-
    awareness rule, soft-deleted asset exclusion, group creation, multiple
    checksums, idempotency, existing resolved groups, status lifecycle,
    progress tracking, Sidekiq queue name.
  - `spec/requests/api/v1/duplicate_manager_settings_spec.rb` — expanded with
    `scan_status`, `trigger_scan`, auto-trigger-on-enable, and no-trigger-when-
    already-enabled scenarios.
  - `spec/factories/asset_versions.rb` — new factory for `AssetVersion` with
    `:with_checksum` trait.

#### Duplicate Manager (SHA-256 based) — from previous session
- **`duplicate_groups` + `duplicate_group_assets` tables** (migration
  `20260626130000`) — persistent storage for detected duplicate asset groups.
- **`DuplicateGroup` model** — lifecycle: `pending → resolved | dismissed`;
  `DuplicateGroup::DISPLAY_LIMIT = 100` caps UI/API list queries.
- **`DuplicateGroupAsset` model** — join table; `is_original: true` flags the
  oldest copy in each group.
- **`DuplicateDetectionService`** — called after every processed upload;
  looks up existing SHA-256 checksums, creates/updates groups, marks the
  original, and fires an Inbox notification when enabled.
- **`DuplicateDetectionWorker`** — Sidekiq worker (queue: `duplicate_detection`)
  that calls `DuplicateDetectionService` asynchronously after
  `AssetProcessorWorker` extracts the SHA-256 checksum.
- **REST API** — `GET/PATCH /api/v1/duplicate_manager_settings` (enable/disable,
  inbox notifications); `GET /api/v1/duplicate_groups` (list, stats, filter),
  `GET /api/v1/duplicate_groups/:id` (detail + member assets),
  `PATCH /api/v1/duplicate_groups/:id/resolve` (keep all or delete selected),
  `PATCH /api/v1/duplicate_groups/:id/dismiss`,
  `PATCH /api/v1/duplicate_groups/bulk_resolve`.
- **GraphQL** — `duplicateGroups(status:)` connection, `duplicateGroup(id:)`
  query, `duplicateManagerStats` query, and `resolveDuplicateGroup` mutation.
- **"Duplicate Manager Settings" panel** under `Tools → Asset Configurations`
  — toggle enable/disable (default: off) and inbox notifications with live
  save; performance-impact warning shown.
- **`DuplicateManager` page** rewritten — real API calls, stats row, filter
  tabs (Pending / Resolved / All), skeleton loading, empty state.
- **`DuplicateResolutionModal`** rewritten — original-badge (⭐) on oldest
  copy, per-asset navigate-to-asset (↗) and go-to-folder (📁) icons, confirm
  delete flow, dismiss action, i18n throughout.
- **i18n** — `duplicateManager.*`, `tools.assetConfigurations.*`, and
  `common.refresh` keys added to all 9 locale files (en, de, fr, es, ja, ko,
  nl, pt, zh).
- **Specs** — `spec/models/duplicate_group_spec.rb`,
  `spec/services/duplicate_detection_service_spec.rb`,
  `spec/workers/duplicate_detection_worker_spec.rb`,
  `spec/requests/api/v1/duplicate_groups_spec.rb`,
  `spec/requests/api/v1/duplicate_manager_settings_spec.rb`.
- **FactoryBot factories** — `duplicate_group` (traits: `:resolved`,
  `:dismissed`) and `duplicate_group_asset` (trait: `:original`).

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
- **Admins could accidentally suspend their own account** — the
  `POST /admin/users/:id/toggle_status` endpoint had no self-protection check
  (unlike `DELETE /admin/users/:id`), so clicking "Suspend Access" on your own
  user row would lock you out with "Account is deactivated." on next login.
  This was the root cause of the Playwright `users_and_groups.e2e.spec.js`
  "suspend / restore user via drawer" test deactivating `admin@admin.com` in
  CI/local runs (it targeted the first DataGrid row, which is the signed-in
  admin). Fixed by:
  - `Admin::UsersController#toggle_status` now returns `403 Forbidden`
    (`"You cannot suspend your own account."`) when suspending your own,
    still-active account; reactivating (if already inactive) remains allowed.
  - `UserDrawer` disables the "Suspend Access" button (with tooltip) when the
    drawer's target user matches the signed-in `currentUserId`.
  - The e2e test now creates a disposable local user for the suspend/restore
    flow instead of touching the first (admin) grid row, and restores it back
    to active before finishing; a new test asserts the button is disabled for
    the logged-in admin's own row.
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

