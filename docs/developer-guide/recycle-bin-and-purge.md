# Recycle Bin & Automatic Purge

This document describes the Recycle Bin subsystem: how soft-deleted assets and
folders are surfaced, how they are permanently purged, and the enterprise
controls that govern that process.

> **Audience:** developers and administrators.
> **Related code:** `app/controllers/api/v1/bin_controller.rb`,
> `app/services/bin_purge_service.rb`, `app/workers/bin_purge_worker.rb`,
> `app/javascript/components/Bin/**`,
> `app/javascript/components/Tools/AssetConfigurations/BinPurgeSettings.jsx`.

---

## Overview

Assets and folders are **never** hard-deleted by end users. They are
soft-deleted via the `SoftDeletable` concern (`deleted_at` timestamp) and land
in the **Recycle Bin** (`/bin`). A scheduled background job permanently removes
items once they exceed the retention window.

```
delete (UI)  ─►  soft-delete (deleted_at set)  ─►  Recycle Bin
                                                       │
                          retention window elapses     ▼
                                          BinPurgeWorker → BinPurgeService
                                                       │
                                          permanent deletion (DB + storage)
```

---

## Retention policy

The policy is stored in the `settings` table and is fully configurable from
**Tools › Asset Configurations › Recycle Bin & Purge** (admin only).

| Setting key | Default | Meaning |
|-------------|---------|---------|
| `bin_retention_days` | `30` | Items deleted ≥ N days ago are eligible for purge |
| `bin_workflow_behavior` | `"skip"` | `"skip"` or `"force_terminate"` (see below) |
| `bin_purge_batch_size` | `50` | `find_each` batch size |
| `bin_purge_notify_admins` | `true` | Notify all admins after each run |

The nightly job runs at **03:00 UTC** (`config/schedule.rb`).

---

## Active-workflow protection

An asset that is still progressing through an approval/review workflow must not
be silently destroyed. `BinPurgeService` inspects each asset's
`workflow_instances` and treats the statuses
`pending`, `in_progress`, `in_review` as **active**.

- **`skip`** *(default)* — the asset is left in the bin and counted under
  `skipped`. Admins are told why (`reason: "active_workflow"`).
- **`force_terminate`** — active workflow instances are stamped `terminated`
  (with an audit-log entry), all `pending` workflow tasks are `cancelled`, and
  the asset is then purged. **This is irreversible** and surfaced with a
  warning in the UI.

---

## Reference integrity & version handling

Before an asset's database row is destroyed, `BinPurgeService` cleans up all
satellite records in a safe order inside a transaction:

1. **DuplicateGroupAsset** memberships are removed. If a duplicate group drops
   below two members it is auto-resolved (`status: :resolved`).
2. **CollectionAsset** rows are removed.
3. **Physical storage files** are deleted for **every `AssetVersion`** (not just
   the active one) via the configured `StorageManager` adapter
   (S3 / GCS / Azure / local), plus any legacy ActiveStorage blobs. Reclaimed
   bytes are accumulated and reported.
4. The `assets.active_version_id` foreign key is nullified **before** the
   destroy cascade — otherwise PostgreSQL raises a `ForeignKeyViolation`
   because the asset still references one of the versions it is about to delete.
5. `asset.destroy!` cascades to versions, embedding, workflow instances/tasks.

`AuditLog` rows are intentionally **preserved** — they are compliance records
and must survive asset deletion.

Per-item failures are isolated: a single failure is logged and counted under
`failed`, and the run continues with the remaining items.

---

## Concurrency & status tracking

A distributed lock is implemented with the `bin_purge_status` setting:
`idle → queued → running → completed | failed`. A second job that starts while
one is `running` exits immediately.

Each run records **who triggered it** in `bin_purge_triggered_by`:

```jsonc
{
  "user_id":      42,
  "user_name":    "Alice Admin",
  "user_email":   "alice@example.com",
  "source":       "manual",        // or "scheduled"
  "triggered_at": "2026-06-26T13:00:00Z"
}
```

The Recycle Bin page (`/bin`) shows a **live banner only while a purge is
running or queued**, including who triggered it; it polls
`GET /api/v1/bin/purge_status` every 3 s and stops automatically when the run
finishes (then refreshes the list).

---

## REST API

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/v1/bin` | List trashed items (search / type / sort / pagination) |
| GET | `/api/v1/bin/stats` | Aggregate stats |
| POST | `/api/v1/bin/bulk_restore` | Restore `[{id, type}]` |
| DELETE | `/api/v1/bin/bulk_destroy` | Permanently delete `[{id, type}]` |
| DELETE | `/api/v1/bin/empty` | Permanently delete everything |
| GET | `/api/v1/bin/retention_policy` | Read policy |
| PUT | `/api/v1/bin/retention_policy` | Update policy *(admin)* |
| POST | `/api/v1/bin/trigger_purge` | Enqueue a purge now *(admin)* — `409` if already running |
| GET | `/api/v1/bin/purge_status` | Status + last-run results + `triggered_by` |
| GET | `/api/v1/bin/ai/smart_suggestions` | AI-ranked safe-to-delete candidates *(admin)* |
| GET | `/api/v1/bin/ai/cleanup_report` | AI cleanup report *(admin)* |

> **ID note:** assets use **UUID** primary keys and folders use **bigint** keys.
> Bin endpoints accept the raw `id` and must **not** coerce it with `.to_i`
> (doing so silently turns a UUID into `0`).

---

## GraphQL

- Queries: `binStats`, `binRetentionPolicy`, `binPurgeStatus`,
  `binAiSuggestions(limit:)`.
- Mutations: `bulkRestoreFromBin`, `emptyBin`, `updateBinRetentionPolicy`,
  `triggerBinPurge`.

`binPurgeStatus` exposes `triggeredBy` for the same audit display as REST.

---

## AI roadmap (Capri AI Gateway)

The AI endpoints are **stubs today** and return a rule-based heuristic ranking
so the UI surface is ready. Once connected to the
[Capri AI Gateway](https://github.com/Capri-Labs/capri-dam-ai-gateway) they will
provide:

- **Smart suggestions** — ML-ranked safe-to-delete assets (usage, age,
  duplication, semantic content).
- **Risk scoring** (`ai_risk_score`) — confidence that an asset is no longer
  needed, plus a natural-language `ai_reason`.
- **Cleanup reports** — LLM-written summaries of what was removed, storage
  reclaimed, and anomaly detection (e.g. unusual bulk-deletion patterns).

Heuristic score (interim) is computed from age, size, collection-pin presence,
and active-workflow status; assets with an active workflow score `0` and are
never suggested.

---

## Testing

| Layer | File |
|-------|------|
| Service | `spec/services/bin_purge_service_spec.rb` |
| Worker | `spec/workers/bin_purge_worker_spec.rb` |
| REST | `spec/requests/api/v1/bin_spec.rb` |
| E2E | `spec/e2e/bin.e2e.spec.js` |

Run them with:

```bash
bundle exec rspec spec/services/bin_purge_service_spec.rb \
                  spec/workers/bin_purge_worker_spec.rb \
                  spec/requests/api/v1/bin_spec.rb
yarn playwright test spec/e2e/bin.e2e.spec.js
```

