# Changelog

All notable changes to Capri DAM are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

#### Deployment Guides — AWS and Azure/Kubernetes
- Renamed `docs/deployment-guide/` → `docs/deployment-guide-kamal/` to make the
  provider explicit now that multiple deployment targets are documented.
- **New `docs/deployment-guide-aws/`** — full 10-chapter production playbook for
  AWS: ECS on Fargate (web + Sidekiq worker services), Aurora PostgreSQL
  (pgvector-compatible), ElastiCache for Redis, S3 (using the already-shipped
  `StorageAdapters::S3Adapter`, no code changes), ALB + ACM for TLS, ECR image
  registry, Secrets Manager for `RAILS_MASTER_KEY`/`DATABASE_URL`/`REDIS_URL`,
  CloudWatch Logs/alarms + ECS Exec for monitoring, and Aurora/S3
  backup & disaster-recovery procedures.
- **New `docs/deployment-guide-azure-kubernetes/`** — full 10-chapter production
  playbook for Azure: AKS `Deployment`/`Service`/`Ingress`/`HorizontalPodAutoscaler`
  manifests, Azure Database for PostgreSQL Flexible Server (pgvector-compatible),
  Azure Cache for Redis, Azure Blob Storage (using the already-shipped
  `StorageAdapters::AzureAdapter`, no code changes), ACR image registry, Azure Key
  Vault + Secrets Store CSI Driver (or plain Kubernetes `Secret`) for credentials,
  ingress-nginx + cert-manager for TLS, Azure Monitor/Container Insights for
  monitoring, and Flexible Server/Blob Storage backup & disaster-recovery
  procedures.
- Updated `docs/index.adoc` documentation hub: three deployment-guide cards
  (Kamal 🚀 / AWS ☁️ / Azure &amp; Kubernetes ⎈), a new **"Choosing a deployment
  target"** comparison table (ops complexity, team skill fit, scaling model,
  managed data services, cost, deploy/rollback mechanism, portability), and
  updated quick-links/plain-text fallback lists.
- Updated `docs/architecture/src/07_deployment_view.adoc` to reference all three
  guides instead of only Kamal.
- Updated `.github/workflows/main.yml` "Build docs site" job to build HTML + PDF
  for all three deployment guides (previously only Kamal) — all three are
  published to GitHub Pages by the existing `deploy-pages` job with no further
  changes required there.
- **New Developer Guide chapter** `docs/developer-guide/src/28_environment-variables.adoc`
  — canonical reference for every environment variable Capri DAM reads
  (required secrets, app configuration, background-job/server tuning, auth/SSO,
  optional third-party integrations, ActiveRecord encryption), including a
  cross-reference table showing how each variable is wired in the Kamal, AWS,
  and Azure/Kubernetes guides, and a note that the active storage backend is
  configured in-app (not via environment variables).

#### Collections — Smart Rules & Access Governance
- **Smart-collection metadata/tag-based routing** (`CollectionRule#match_mode`):
  rules can now route assets by `semantic` (AI embedding similarity, original
  behavior), `metadata` (pure tag/property matching via `metadata_filters`, no
  AI involved — works immediately on save), or `hybrid` (must satisfy both).
  Metadata filters support "AND across keys, OR within an array value" — e.g.
  `{ "tags" => ["Q3 Campaign", "Social Media"] }` matches either tag.
  `SmartCollectionRouterWorker` and the new `CollectionRuleBackfillWorker`
  (re-evaluates existing assets against a rule after it's created/edited)
  implement the matching logic.
- **`GraphQL::Mutations::ConfigureCollectionRule`** — create/update a
  collection's smart rule (match mode, semantic prompt, metadata filters,
  similarity threshold) from the Workspace Properties UI.
- **Collection Access Governance** (`CollectionPolicy` model) — replaces the
  dummy Access Governance data on the Collections → Workspace Properties
  screen with real `UserGroup`-based permissions:
  - Four tiers per group/collection pair: `view_access` (Viewer),
    `edit_access` (Editor, implies Viewer), `admin_access` (Collection Admin —
    configure rules, manage access, delete/archive workspace; implies Editor),
    and `explicit_deny` (short-circuits all access for that group even if
    another group grants it).
  - Creating even one `CollectionPolicy` row switches a collection from
    legacy open/allow-list access (`allowed_groups`/`denied_groups` JSONB
    arrays) into **strict group-governed mode** — only groups with an
    explicit, non-denied policy may access it (`Collection#accessible_by?`).
  - Lets admins scope a user group to exactly one collection (or a subset),
    separate from default/sys-admin roles — sys admins and default admins
    retain override access; collection-admins are scoped to their own
    collection(s) only.
  - `Types::CollectionPolicyType`, `Types::CollectionRuleType` GraphQL types
    added; `Types::CollectionType`/`Types::MutationType` updated.
  - `db/migrate/20260716080551_add_match_mode_to_collection_rules.rb` and
    `db/migrate/20260716080552_create_collection_policies.rb`.

#### Cascading Metadata Schema Rules
- Metadata schema fields now support three dynamic, admin-configurable rule
  types (matching the requirement/visibility/choices pattern from mainstream
  DAM products), all editable from the in-app Metadata Schema editor with no
  code changes required:
  - **Requirement** — a field becomes conditionally required based on the
    selected value of another dropdown field (e.g. "Copyright Owner" required
    only when "License Requirements" = "Licensed").
  - **Visibility** — a field is shown/hidden based on the value of another
    dropdown field (e.g. a "State" dropdown only appears when "Country" =
    "United States").
  - **Choices** — a dropdown's available options are filtered based on the
    value of a related dropdown (e.g. "City" choices narrow to match the
    selected "State").
- Rules are stored and evaluated declaratively — administrators configure
  them entirely through the UI.

#### Reports — Folder Filter
- Added a multi-select folder search box next to the date range field on
  `/reports`, allowing selection of multiple folder paths via an overlay;
  `AnalyticsDashboard.jsx`/`ReportFolderFilter.jsx` and
  `Reports::AnalyticsService`/`Admin::ReportsController` updated so all report
  metrics scope to the selected folders.

#### User Groups — Pagination
- Added server-side pagination to `/admin/user_groups`, matching the pattern
  used elsewhere in the admin UI.

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
- **Inbox download link not working** — the download action on `/inbox` was
  wired to a route/handler that didn't correctly resolve the asset's file for
  download; fixed the routing/controller logic so clicking "Download" from an
  inbox notification correctly streams the asset.
- **Command Center dashboard — "Assets by Type" chart loading incorrectly** —
  fixed the data query/serialization feeding the Assets-by-Type chart on
  `/dashboard` so it renders the correct breakdown instead of failing to load.
- **Command Center dashboard — "Storage Used" widget showed no data** — fixed
  the storage-usage aggregation query so the widget displays real totals.
- **Recent Assets showed 0 KB for file size** — asset file size wasn't being
  read/serialized correctly for the Recent Assets list; now reflects actual
  size. The same underlying dashboard/reports data issues (Assets by Type,
  Storage Used, asset size) were also present on `/reports` and fixed via the
  shared `Reports::AnalyticsService`.
- **Duplicate Manager showed groups with only 1 remaining asset** — "Resolve
  Duplicates" cards could still appear after a duplicate asset was deleted,
  leaving a group with fewer than the required 2 members. Groups now
  auto-resolve (or are removed from the active list) when membership drops
  below 2 assets, so the Duplicate Manager stays in sync with asset
  deletions/removals in real time.
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
- **Lexical search had no supporting index (`ILIKE` table scan)** —
  `Api::V1::SearchController`'s keyword/faceted search ran `ILIKE`/JSONB
  text-extraction queries with no index backing them (the existing
  `properties` GIN index only supports containment/key-existence operators,
  not `->>` + `ILIKE`). Added migration
  `20260716113000_add_trigram_search_indexes_for_lexical_search` enabling
  `pg_trgm` and adding GIN trigram indexes on `assets.title`,
  `properties->>'original_filename'`, `properties::text`,
  `properties->>'content_type'`, and `folders.name` — preserves existing
  substring-match semantics while making every search query-plan
  index-backed (verified via `EXPLAIN`). See ADR 3
  (`docs/architecture/src/09_design_decisions.adoc`) and the "Lexical search
  has no index" row in `docs/architecture/src/11_technical_risks.adoc`.
- **OpenAPI/Pact schema type drift on `Folder#id`** — `swagger/v1/swagger.yaml`
  documented `folders[].id` (and the nested `assets[].id` in the folder
  `show` response) as `type: integer`, but both `Folder` and `Asset` use UUID
  string primary keys, causing Pact provider verification to fail with
  `expected integer, but received String`. Fixed the rswag annotations in
  `spec/requests/api/v1/folders_spec.rb` and regenerated
  `swagger/v1/swagger.yaml` via `make swagger-docs`.

[Unreleased]: https://github.com/your-org/headless-dam/compare/main...HEAD

