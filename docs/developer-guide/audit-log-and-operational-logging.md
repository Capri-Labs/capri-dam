# Audit Log & Operational Logging (Custom Log Level)

This document describes two related-but-independent "log" subsystems:
the immutable **Audit Log** trail, and the dynamic global **Operational
Logging** (log level) control.

> **Audience:** developers and administrators.
> **Related code:** `app/models/audit_log.rb`, `app/models/concerns/auditable.rb`,
> `app/jobs/prune_audit_logs_job.rb`, `app/controllers/admin/audit_logs_controller.rb`,
> `app/javascript/components/Admin/SystemStatus/AuditLogTab.jsx`,
> `app/models/system_configuration.rb`, `app/controllers/admin/system_configurations_controller.rb`,
> `app/javascript/components/Admin/SystemStatus/OperationalLoggingTab.jsx`.

---

## 1. Audit Log

### Overview

Every create/update/destroy on a model that `include`s the `Auditable`
concern is automatically written to `audit_logs` as a row that records who
did it, what changed, and — critically — whether it happened while an admin
was impersonating another user (non-repudiation).

```
User#save/#destroy  ─►  Auditable callback  ─►  AuditLog.create!
                                                     │
                                    user_id (actor), true_user_id (real actor
                                    when impersonating), action, auditable_type/id,
                                    changes_data, ip_address, user_agent
```

Currently only `User` includes `Auditable`. Administrative actions that
don't map to a single model save (impersonation grants/revokes, PAT
revocations, etc.) are recorded explicitly via `AuditLog.record(...)`.

Entries are only written when `Current.user` is present — background jobs,
rake tasks, and seeds run without a request context and are silently
skipped, so a missing actor never causes an unrelated transaction to roll
back.

### Immutability

`audit_logs` carries a Postgres trigger (`trigger_protect_audit_logs`,
added in `db/migrate/20260527142102_add_immutability_to_audit_logs.rb`) that
raises on **every** `UPDATE` or `DELETE`, so application code — including
bugs — can never silently tamper with or lose an audit trail entry.

> **⚠️ Schema format gotcha (fixed):** `db/schema.rb` (Rails' Ruby schema
> dump) cannot represent raw SQL objects like triggers or functions. Because
> this app previously used `schema_format: :ruby`, any database rebuilt via
> `db:schema:load` / `db:prepare` / `db:test:prepare` — i.e. every fresh dev
> setup and CI run — silently **did not** have this trigger, even though the
> migration was recorded as applied. The app now sets
> `config.active_record.schema_format = :sql` (see `config/application.rb`),
> so `db/structure.sql` is the source of truth and round-trips the trigger
> correctly. Run `bin/rails db:schema:dump` after any migration that adds
> raw SQL (triggers/functions/views) and commit the updated
> `db/structure.sql`.

### Retention

`PruneAuditLogsJob` deletes rows older than 90 days. Because the table is
immutability-protected, the job must explicitly disable the trigger for the
duration of the delete and re-enable it afterwards (in an `ensure` block, so
the table is never left unprotected even if the delete raises):

```ruby
def perform
  disable_immutability_trigger!
  AuditLog.where("created_at < ?", RETENTION_PERIOD.ago).delete_all
ensure
  enable_immutability_trigger!
end
```

Schedule this job periodically (e.g. via `sidekiq-cron` or a recurring
`ActiveJob` schedule) — it is not currently wired to an automatic scheduler.

### Admin viewer (`Admin::AuditLogsController`)

`GET /admin/audit_logs` (admin-only) lists entries with pagination and
filters:

| Param | Meaning |
|-------|---------|
| `user_id` | Acting user |
| `audit_action` | `create` / `update` / `destroy` / custom recorded actions — **not** `action`, which is a reserved Rails routing param |
| `auditable_type` | Audited model class name (e.g. `Folder`) |
| `impersonated` | `true`/`false` — actions taken while impersonating |
| `date_from` / `date_to` | Created-at range (inclusive) |
| `search` | Free-text match across actor email, action, and resource type |
| `page` / `per_page` | Pagination |

The React viewer lives in **Settings → System Operations → Audit Trail**
(`AuditLogTab.jsx`).

---

## 2. Operational Logging (dynamic global log level)

### Overview

`SystemConfiguration` is a generic key/value config record with an optional
TTL and fallback value. The `global_log_level` key drives the app's runtime
log verbosity without a restart:

```
Admin sets level + TTL (UI)
        │
        ▼
Admin::SystemConfigurationsController#update_logging
        │
        ▼
SystemConfiguration#after_commit ── Sidekiq.redis { |c| c.publish("system_config_updates", payload) }
        │
        ▼
All Puma worker processes subscribed to that channel update their in-process log level
```

`GET /admin/system_configurations/logging` returns the current level,
fallback, and remaining TTL minutes; `POST` updates it. The UI is
`OperationalLoggingTab.jsx` (Settings → System Operations → Operational
Logging).

### Known limitations / follow-ups

- The Redis broadcast is wrapped in a bare `rescue nil` — a Redis/Sidekiq
  outage will silently fail to broadcast the new level to running workers
  (the DB row still updates). Worth alerting on if this matters for your
  deployment.
- `Auditable` is only included on `User` today. Expanding it to other
  high-value models (e.g. `Folder`, `Collection`) would give a fuller
  audit trail but was intentionally left out of this pass — it increases
  write volume and needs a retention/perf review first.

---

## Testing

| Layer | File |
|-------|------|
| Model | `spec/models/audit_log_spec.rb`, `spec/models/system_configuration_spec.rb` |
| Job (real DB trigger, not mocked) | `spec/jobs/prune_audit_logs_job_spec.rb` |
| REST | `spec/requests/admin/audit_logs_spec.rb`, `spec/requests/admin/system_configurations_spec.rb` |
| Swagger/OpenAPI | `spec/requests/admin/audit_logs_swagger_spec.rb` |
| Jest | `spec/javascript/components/Admin/SystemStatus.test.jsx` (`AuditLogTab`, `OperationalLoggingTab`) |
| E2E | `spec/e2e/audit_log.e2e.spec.js` |

Run them with:

```bash
bundle exec rspec spec/models/audit_log_spec.rb \
                  spec/models/system_configuration_spec.rb \
                  spec/jobs/prune_audit_logs_job_spec.rb \
                  spec/requests/admin/audit_logs_spec.rb \
                  spec/requests/admin/system_configurations_spec.rb
yarn jest spec/javascript/components/Admin/SystemStatus.test.jsx
yarn playwright test spec/e2e/audit_log.e2e.spec.js
```

After adding/changing any `admin/audit_logs` or `admin/system_configurations`
endpoint, regenerate the OpenAPI docs with `make swagger-docs` (or the
combined `make api-docs`).

### i18n

Both admin UI tabs are fully wired through `react-i18next` (`operationalLogging.*`
and `auditLog.*` keys). All 10 supported locales (`en`, `de`, `es`, `fr`, `pt`,
`nl`, `ja`, `zh`, `ko`, `ar`) have translations for both key trees under
`app/javascript/i18n/locales/`. `spec/javascript/i18n/i18n.test.js` enforces
key parity across every locale (any new key added to `en.json` must be
back-filled in the other 9 files or that spec fails), so this coverage is
regression-tested going forward.
