# AI-Gateway: Capri DAM Integration Prompt

> **How to use**: Copy this entire file and paste it as the task prompt when
> working in the `capri-dam-ai-gateway` repository.  It documents every
> contract the Rails monolith (`headless-dam`) expects the gateway to honour.

---

## Context: AI screens that talk to this gateway

The Rails monolith exposes several AI screens that talk to this gateway:

| Screen | Route | Who | Purpose |
|---|---|---|---|
| **Semantic Copilot** | `/ai/copilot` | All authenticated users | Natural-language asset discovery via vector search |
| **Agent Automations** | `/ai/agents` | Admins only | Define autonomous agent pipelines that fire on DAM events |
| **AI Batch Tasks** | `/ai/tasks` (legacy `/ai/batch`) | Admins only | Run an AI task across a whole dataset on demand and track live progress |
| **Prompt Playground** | `/ai/lab/playground` | Admins only | Raw LLM prompt engineering workbench |
| **Provenance & C2PA** | `/ai/governance/provenance` | Admins only | C2PA manifest verification, signing, AI-disclosure auditing, policy settings |
| **Style & Model Hub** | `/ai/models/hub` (alias `/ai/models`) | Admins only | Register AI model endpoints, manage brand style presets, launch style batch tasks |

These screens hit different gateway endpoints.  Keep them clearly separated in
the gateway implementation.

---

## Architecture

```
Browser → Rails (headless-dam) → AI Gateway (this repo)
                                         ↓
                                  OpenAI / Anthropic / Ollama
```

Rails never calls any AI provider directly.  All inference is proxied through
this gateway.  The gateway:

1. Accepts HTTP requests from Rails.
2. Dispatches to the configured AI provider.
3. Returns **normalised JSON** regardlfess of provider.
4. Listens on Redis pub/sub channel `ai_gateway_events` for live config updates.

Rails reaches the gateway at `AI_GATEWAY_URL` (default `http://localhost:8000`).
Provider API keys live **only** in the gateway — never in Rails.

---

## Required HTTP endpoints

### 1. `POST /api/embed_query`

Translates a text string into a dense float vector.  Called by:
- `Api::V1::CopilotsController#search` (user-facing semantic search)
- `IngestionWorker` (embedding newly uploaded assets)

**Request**
```json
{ "text": "Wide shots of urban architecture at night" }
```

**Response `200 OK`**
```json
{
  "vector": [0.012, -0.345, 0.198, ...],
  "model":  "text-embedding-3-small",
  "tokens": 9
}
```

**Error responses**
- `422` — `text` is blank
- `503` — upstream provider unreachable

**Constraints**
- Vector dimension must match the `embeddings` column in `asset_embeddings`
  (384 for MiniLM, 1536 for `text-embedding-3-small`).
- Must honour the active embedding model from the latest `gateway.config.updated` event.
- Target latency: < 500 ms p95.

---

### 2. `POST /api/tdm/evaluate`

TDM (Training Data & Model provenance) evaluation.  Called by `IngestionWorker`
for every staged asset before it is accepted into the DAM.

**Request**
```json
{
  "filename": "hero_banner.jpg",
  "metadata": {
    "mime_type": "image/jpeg",
    "file_size": 2097152,
    "exif": { "Make": "Canon", "GPS": null },
    "custom_properties": {}
  }
}
```

**Response `200 OK`**
```json
{
  "tdm_safe":        true,
  "confidence":      0.92,
  "flags":           [],
  "summary":         "No watermarks detected. EXIF origin verified.",
  "recommendations": []
}
```

| Field | Type | Description |
|---|---|---|
| `tdm_safe` | boolean | `true` = safe to ingest |
| `confidence` | float 0–1 | Model confidence |
| `flags` | `string[]` | e.g. `["watermark_detected", "stock_origin"]` |
| `summary` | string | Human-readable verdict |
| `recommendations` | `string[]` | Remediation steps |

**Side-effects**
- `tdm_safe: false` causes Rails to automatically quarantine the asset.
- Result is stored in `ingestion_items.ai_evaluation` (JSONB).

---

### 3. `POST /v1/chat`

General-purpose chat-completion.  Used by the **Prompt Playground** (admin only).

**Request**
```json
{
  "messages": [
    { "role": "system",    "content": "You are an enterprise data steward." },
    { "role": "user",      "content": "Suggest 5 SEO tags for a beach photo." }
  ],
  "model":       "gpt-4o-mini",
  "temperature": 0.7,
  "max_tokens":  1024
}
```

**Response `200 OK`** — mirrors OpenAI chat completions shape:
```json
{
  "id":      "chatcmpl-abc123",
  "model":   "gpt-4o-mini",
  "choices": [
    {
      "index": 0,
      "message": {
        "role":    "assistant",
        "content": "1. beach 2. ocean 3. summer 4. waves 5. sunset"
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens":     42,
    "completion_tokens": 18,
    "total_tokens":      60
  }
}
```

**Error responses**
- `400` — `messages` missing or malformed
- `422` — unknown model
- `402` — monthly budget cap reached
- `503` — all providers down

**Constraints**
- `temperature` clamped to `[0.0, 2.0]`
- `max_tokens` clamped to `[1, 8192]`
- Fallback to local LLM when `fallback_to_local: true` in config

---

## Redis pub/sub channel: `ai_gateway_events`

The gateway must subscribe to this channel and react in real time.

### `gateway.config.updated`

Sent whenever an admin updates `AiConfiguration`.

```json
{
  "event": "gateway.config.updated",
  "config": {
    "active_provider":    "openai",
    "generation_model":   "gpt-4o",
    "embedding_model":    "text-embedding-3-small",
    "monthly_budget_usd": 200.0,
    "current_spend_usd":  42.5,
    "system_prompt":      "You are an enterprise data steward...",
    "fallback_to_local":  true
  }
}
```

On receipt → hot-swap provider/model without restart, enforce budget cap, update
default system prompt.

### `asset.needs_embedding`

Emitted from the `Asset` model after every create/update that touches `properties`.

```json
{
  "event":      "asset.needs_embedding",
  "asset_uuid": "550e8400-e29b-41d4-a716-446655440000"
}
```

The gateway **should** proactively generate and POST the embedding back to Rails:
```
POST /api/v1/assets/{uuid}/embedding  (requires AI_GATEWAY_SECRET header)
Body: { "vector": [...] }
```

This decouples embedding generation from user-facing request latency.

### `asset.staged` / `asset.updated`

```json
{
  "event":      "asset.staged",
  "asset_id":   "uuid-here",
  "filename":   "hero_banner.jpg",
  "mime_type":  "image/jpeg"
}
```

May be used to trigger proactive TDM evaluation or thumbnail analysis.

---

## Agent Workflows (the `/ai/agents` screen)

Admins define **agent workflows** in the DAM — autonomous pipelines that fire
on DAM events and run an AI agent with a configured set of tools.  The gateway
is the **execution engine**: it subscribes to workflow activations and runs the
agent chain when the trigger event occurs.

### Lifecycle

```
Admin toggles a workflow ON  →  Rails publishes "agent_workflow.activated"
        →  Gateway subscribes the workflow to its trigger event
        →  Trigger fires (e.g. asset.staged)
        →  Gateway runs the agent chain (model + tools)
        →  Gateway POSTs the result back to Rails (execution log)
```

### Inbound events (gateway subscribes)

The gateway must handle these messages on `ai_gateway_events`:

#### `agent_workflow.activated`
```json
{
  "event": "agent_workflow.activated",
  "workflow": {
    "id":          12,
    "name":        "Auto-SEO Enrichment",
    "trigger":     "asset.staged",
    "agent_model": "gpt-4o-mini",
    "tools":       ["VisualContextExtractor", "SEOTaxonomyMapper"],
    "metadata":    {}
  }
}
```
Register/refresh an in-memory subscription that maps `trigger` → this workflow.

#### `agent_workflow.deactivated` / `agent_workflow.removed`
```json
{ "event": "agent_workflow.deactivated", "workflow": { "id": 12, ... } }
{ "event": "agent_workflow.removed",     "workflow": { "id": 12 } }
```
Unsubscribe the workflow so it stops reacting to its trigger.

#### `agent_workflow.manual_trigger`
```json
{
  "event":        "agent_workflow.manual_trigger",
  "workflow_id":  12,
  "triggered_by": 4
}
```
Run the workflow once, immediately, regardless of its trigger event.

### Supported trigger events

| Trigger | Fires when |
|---|---|
| `asset.staged`     | A new upload finishes staging |
| `asset.updated`    | Asset metadata changes |
| `schedule.nightly` | Daily cron at 00:00 UTC (the gateway schedules this itself) |
| `manual`           | Only via `agent_workflow.manual_trigger` |

### Outbound: write the execution result back to Rails

After each run (success or failure) the gateway **must** POST the result so the
UI telemetry and reliability/latency stats update:

```
POST {RAILS_BASE_URL}/api/v1/agent_workflows/{id}/executions
Headers:
  X-Gateway-Secret: <GATEWAY_SECRET>
  Content-Type: application/json
Body:
{
  "agent_execution": {
    "trigger_type":    "event",          // "event" | "manual" | "scheduled"
    "trigger_payload": { "asset_id": "uuid-here" },
    "status":          "success",        // running | success | warning | failed
    "summary":         "Mapped 4 semantic tags to hero_banner.jpg",
    "output":          { "tags_added": 4, "asset_id": "uuid-here" },
    "error_message":   null,
    "duration_ms":     1423,
    "started_at":      "2026-06-28T11:12:04Z",
    "completed_at":    "2026-06-28T11:12:05Z"
  }
}
```

- Authenticated **only** by the `X-Gateway-Secret` header (no Devise session).
- Returns `201 Created` on success, `401` on bad secret, `422` on validation error.
- For long runs, you may POST an initial `status: "running"` row, then PATCH is
  not supported — instead POST the final terminal record. (Keep it simple: one
  terminal record per run is sufficient for the telemetry feed.)

### Conventions for `summary`

The UI shows `summary` directly in the telemetry feed, so keep it short and
action-oriented, e.g.:
- `"Mapped 6 semantic tags to urban_skate.jpg"`
- `"Quarantined GettyImages_Draft.png (watermark detected)"` → use `status: "warning"`
- `"Gateway timeout after 30s"` → put in `error_message`, `status: "failed"`

---

## AI Batch Tasks (the `/ai/tasks` screen)

Admins launch **on-demand batch runs** that apply a single AI task across a whole
segment of the library (e.g. "Metadata Extraction over all images").  Each run is
persisted in Rails as an `ai_batch_jobs` row.  Rails resolves the target dataset,
records the total, marks the job `running`, then publishes **one** dispatch event
to `ai_gateway_events`.  The gateway processes the targets and **streams progress
back** via a secret-authenticated progress endpoint.

### Task catalogue (gateway capabilities)

The task selector in the UI is data-driven by a Rails registry
(`Ai::BatchTaskRegistry`).  Each task maps to a `capability` string the gateway
must implement:

| Task key | `capability` | What the gateway should do |
|---|---|---|
| `metadata_extraction` | `metadata.extract` | Extract title/description/keywords per asset |
| `seo_enrichment`      | `metadata.seo`     | Generate SEO tags, alt text, captions |
| `visual_context`      | `vision.describe`  | High-fidelity scene/object/mood description |
| `compliance_check`    | `compliance.audit` | Detect watermarks, stock origins, licensing risk |
| `embedding_backfill`  | `embedding.generate` | Generate + POST embeddings for assets without one |

> Adding a task in Rails is a one-line registry change.  Treat `capability` as
> the stable contract; gracefully no-op (and report `failed_count`) on an
> unknown capability rather than crashing the batch.

### Inbound event (gateway subscribes): `ai_batch.dispatch`

```json
{
  "event":        "ai_batch.dispatch",
  "job_id":       42,
  "task_type":    "metadata_extraction",
  "capability":   "metadata.extract",
  "tools":        ["VisualContextExtractor", "JsonSchemaValidator"],
  "target_scope": "missing_metadata",
  "concurrency":  25,
  "options":      {},
  "target_ids":   ["uuid-1", "uuid-2", "..."]
}
```

- `target_ids` are asset UUIDs (capped at 5000 per message; for larger datasets
  the gateway should page using its own cursor against the DAM read API).
- Process the targets in batches of `concurrency`.
- Honour the active provider/model from the latest `gateway.config.updated`.

### Inbound event: `ai_batch.cancelled`

```json
{ "event": "ai_batch.cancelled", "job_id": 42 }
```

Stop processing the job immediately and do not send further progress for it.

### Outbound: stream progress back to Rails

Post progress **periodically** (e.g. after each batch of `concurrency`) and once
more on completion.  Rails recomputes `progress_percent` from the counters and
sets `completed_at` automatically when a terminal `status` is reported.

```
POST {RAILS_BASE_URL}/api/v1/ai_batch_jobs/{job_id}/progress
Headers:
  X-Gateway-Secret: <GATEWAY_SECRET>
  Content-Type: application/json
Body:
{
  "ai_batch_job": {
    "status":          "running",     // running | completed | failed | paused
    "processed_count": 60,
    "succeeded_count": 58,
    "failed_count":    2,
    "error_message":   null           // set with status: "failed" on a fatal error
  }
}
```

- Authenticated **only** by the `X-Gateway-Secret` header (no Devise session).
- `total_count` is owned by Rails — do **not** send it; only send counters/status.
- Returns `200 OK` on success, `401` on bad secret, `422` on validation error.
- Send a final `status: "completed"` (or `"failed"`) when the run ends so the UI
  stops polling.


## Content Provenance & C2PA (`/ai/governance/provenance` screen)

Admins configure and monitor **C2PA (Coalition for Content Provenance and
Authenticity)** compliance from this screen.  The gateway is the execution
engine for three capabilities: manifest verification, manifest signing, and
AI-disclosure auditing.

### C2PA policy configuration (`c2pa.config.updated`)

Emitted on `ai_gateway_events` whenever an admin saves the C2PA policy.

```json
{
  "event": "c2pa.config.updated",
  "config": {
    "gateway_c2pa_enabled":    true,
    "auto_verify_on_ingest":   true,
    "auto_sign_on_ingest":     false,
    "ai_disclosure_required":  true,
    "signing_issuer_name":     "Capri DAM",
    "signing_org":             "Acme Corp",
    "trust_store_urls":        ["https://certs.adobe.com/rootcerts.pem"],
    "verification_strictness": "strict"
  }
}
```

On receipt → hot-swap verification parameters without restart.

### Individual asset verification (`asset.c2pa_verify`)

Emitted by `AssetProvenanceWorker` when `auto_verify_on_ingest` is enabled
and a single asset needs verification (e.g. immediately after ingest).

```json
{
  "event":    "asset.c2pa_verify",
  "asset_id": "550e8400-e29b-41d4-a716-446655440000",
  "options": {
    "strictness":             "strict",
    "ai_disclosure_required": true,
    "signing_enabled":        false
  }
}
```

The gateway processes the asset and **must** call back with a single-element
`bulk_upsert` payload (see outbound section below).

### C2PA capability catalogue

The task catalogue in `Ai::BatchTaskRegistry` maps to the following gateway
capabilities:

| Task key             | `capability`       | What the gateway must do |
|----------------------|--------------------|--------------------------|
| `c2pa_verify`        | `c2pa.verify`      | Parse and cryptographically verify C2PA manifests; detect AI-generated / AI-modified flags |
| `c2pa_sign`          | `c2pa.sign`        | Generate a new C2PA manifest, sign with the configured DAM identity, embed or link it |
| `ai_disclosure_audit`| `disclosure.audit` | Identify assets that are AI-generated/modified but lack required AI disclosure assertions |

These are dispatched via the existing `ai_batch.dispatch` / `ai_batch.cancelled`
event infrastructure (same shape as other batch tasks).

### Manifest status values returned by the gateway

| `manifest_status`  | Meaning |
|--------------------|---------|
| `verified`         | Valid C2PA manifest; all signatures check out |
| `ai_generated`     | Valid manifest; asset is wholly AI-generated |
| `ai_modified`      | Valid manifest; asset was AI-modified after creation |
| `missing`          | No C2PA manifest found in the file |
| `invalid`          | Manifest present but cryptographic verification failed |
| `signed`           | DAM identity successfully embedded via `c2pa.sign` |
| `error`            | Gateway processing error (put detail in `error_detail`) |

### Outbound: write C2PA results back to Rails

After processing each batch (or each individual `asset.c2pa_verify` event)
the gateway **must** POST results to Rails:

```
POST {RAILS_BASE_URL}/api/v1/asset_provenance_records/bulk_upsert
Headers:
  X-Gateway-Secret: <GATEWAY_SECRET>
  Content-Type: application/json
Body:
{
  "records": [
    {
      "asset_id":                "550e8400-e29b-41d4-a716-446655440000",
      "manifest_status":         "verified",
      "manifest_data":           { ... full parsed C2PA JSON ... },
      "claim_generator":         "Adobe Photoshop 25.0",
      "is_ai_modified":          false,
      "ai_tools_used":           [],
      "verified_at":             "2026-06-28T12:00:00Z",
      "signed_at":               null,
      "signer_name":             null,
      "signer_cert_fingerprint": null,
      "error_detail":            null
    }
  ]
}
```

- Uses PostgreSQL upsert (`ON CONFLICT DO UPDATE`) — safe to call multiple times.
- `asset_id` is the asset **UUID** string.
- `manifest_data` should contain the full parsed C2PA manifest JSON so the
  admin can inspect it in the UI (key: `manifestData` field in the React table).
- For signing results, include `signed_at`, `signer_name`, and
  `signer_cert_fingerprint` (SHA-256 fingerprint of the leaf certificate).
- For AI-disclosure audit results: set `is_ai_modified: true` and populate
  `ai_tools_used` array with tool names from the C2PA assertion.
- Returns `200 { "upserted": N, "skipped": M }` on success.
- Returns `401` on bad/missing secret, `422` when all records have unknown
  asset IDs.

### C2PA-specific non-functional requirements

| Concern | Requirement |
|---------|-------------|
| Trust store | Download and cache trust-store certificates at startup; refresh daily |
| Signing key | Private key lives in gateway only — never in Rails or logs |
| Manifest size | Cap `manifest_data` at 512 KB before embedding; link externally beyond that |
| Verification latency | p95 < 2 s per asset for `c2pa.verify` (no model call required) |
| Signing latency | p95 < 5 s per asset for `c2pa.sign` |
| C2PA SDK | Use `c2pa-python` (≥ 0.5) or the Rust-backed `c2pa` crate via FFI |

---

## Health check

```
GET /health  →  200 OK
```
```json
{
  "status":    "ok",
  "providers": {
    "openai":    "reachable",
    "anthropic": "reachable",
    "local":     "available"
  },
  "redis":     "connected",
  "uptime_s":  3721
}
```

---

## Authentication

Every inbound request from Rails must include:

```
X-DAM-Gateway-Secret: <shared secret>
```

Shared secret is set via env var `GATEWAY_SECRET` on both Rails and the gateway.
Return `401` if the header is missing or wrong.

---

## Non-functional requirements

| Concern | Requirement |
|---|---|
| Latency | `embed_query` < 500 ms p95; `/v1/chat` < 30 s p99 |
| Retry | Exponential back-off, max 3 attempts, 5xx only |
| Circuit breaker | Open after 5 consecutive failures; retry after 60 s |
| Budget | Accumulate token cost; publish `gateway.spend.updated` to Redis on change |
| Logging | Structured JSON: `event`, `model`, `tokens`, `latency_ms`, `status` per call |
| Observability | Prometheus metrics at `/metrics` |
| Tests | pytest, `httpx.AsyncClient`; ≥ 80% line coverage |
| Secrets | Provider keys never in logs or HTTP responses |

---

## Suggested project structure

```
capri-dam-ai-gateway/
  app/
    main.py
    config.py                   # Pydantic settings (reads env vars)
    routers/
      embed.py                  # POST /api/embed_query
      tdm.py                    # POST /api/tdm/evaluate
      chat.py                   # POST /v1/chat
      health.py                 # GET /health
    providers/
      base.py
      openai_provider.py
      anthropic_provider.py
      local_provider.py         # Ollama / llama-cpp-python
    services/
      router_service.py         # Provider selection + fallback
      budget_service.py         # Token cost tracking
      circuit_breaker.py
      embedding_service.py      # Handles asset.needs_embedding events
    events/
      redis_subscriber.py       # Listens on ai_gateway_events
      handlers.py               # config.updated, asset.needs_embedding
    schemas/
      embed.py
      tdm.py
      chat.py
  tests/
    test_embed.py
    test_tdm.py
    test_chat.py
    test_events.py
    test_auth.py
  Dockerfile
  pyproject.toml
  README.md
```

---

## Environment variables

```dotenv
# Required
OPENAI_API_KEY=sk-...
REDIS_URL=redis://localhost:6379/0
GATEWAY_SECRET=change-me-in-prod

# Optional
ANTHROPIC_API_KEY=sk-ant-...
OLLAMA_BASE_URL=http://localhost:11434
AI_GATEWAY_PORT=8000
LOG_LEVEL=INFO
RAILS_BASE_URL=http://localhost:3000   # for posting embeddings back
```

---

## Acceptance criteria

- [ ] All 4 HTTP endpoints (`embed_query`, `tdm/evaluate`, `v1/chat`, `health`) respond with documented schemas.
- [ ] `X-DAM-Gateway-Secret` validation rejects requests with wrong/missing secret → `401`.
- [ ] Redis subscriber reconnects automatically on disconnect.
- [ ] `gateway.config.updated` hot-swaps provider/model without restart.
- [ ] `asset.needs_embedding` causes the gateway to POST the vector back to Rails.
- [ ] `agent_workflow.activated` / `.deactivated` / `.removed` register/unregister trigger subscriptions.
- [ ] `agent_workflow.manual_trigger` runs the workflow once on demand.
- [ ] After each agent run the gateway POSTs an execution record to `/api/v1/agent_workflows/{id}/executions` with the `X-Gateway-Secret` header.
- [ ] `ai_batch.dispatch` is consumed; the gateway processes `target_ids` in batches of `concurrency` per the task `capability`.
- [ ] The gateway streams progress to `/api/v1/ai_batch_jobs/{job_id}/progress` (counters + status) and sends a final terminal status.
- [ ] `ai_batch.cancelled` halts an in-flight batch job immediately.
- [ ] `schedule.nightly` workflows are run by an internal cron at 00:00 UTC.
- [ ] `c2pa.config.updated` is consumed; the gateway hot-swaps verification parameters.
- [ ] `asset.c2pa_verify` is consumed; the gateway verifies the asset's C2PA manifest and calls back via `bulk_upsert`.
- [ ] `c2pa.verify` batch capability parses and cryptographically verifies manifests; sets `manifest_status` and AI flags.
- [ ] `c2pa.sign` batch capability generates and embeds a signed C2PA manifest with the DAM identity.
- [ ] `disclosure.audit` batch capability identifies AI-generated/modified assets lacking required disclosure.
- [ ] After every C2PA operation the gateway POSTs results to `/api/v1/asset_provenance_records/bulk_upsert` with `X-Gateway-Secret`.
- [ ] `manifest_data` JSONB is capped at 512 KB; assets with larger manifests link externally.
- [ ] Budget cap → `402` when `current_spend_usd >= monthly_budget_usd`.
- [ ] Circuit breaker opens after 5 consecutive provider failures.
- [ ] `pytest` suite passes; coverage ≥ 80%.
- [ ] Dockerfile builds; `docker compose up` starts on port 8000.
- [ ] No API keys in logs or responses.

---

## Style & Model Hub contract

### 7. Style & Model Hub — `/ai/models/hub`

The **Style & Model Hub** is an admin screen for managing AI model endpoints and brand style presets.  It introduces three new gateway capability namespaces and three new Redis event types.

#### 7a. New Redis events to consume

| Event | Payload | Gateway action |
|---|---|---|
| `model.config.updated` | `{ event, config: { id, name, provider, model_id, capability, enabled, is_default, config_params } }` | Hot-reload internal model routing table; apply new defaults without restart |
| `model.health.check` | `{ event, model_id, provider, model_ref, capability, callback_url }` | Run a lightweight health ping against the provider; POST result back to `callback_url` |
| `style.preset.sync` | `{ event, preset: { id, slug, name, description, active, is_default, style_params } }` | Upsert the preset into the gateway's style registry; the DAM **does not** wait for a callback |
| `style.preset.changed` | `{ event, action, preset: { id, slug, name, active, is_default } }` | Invalidate any style-preset caches; remove the preset if `action == "destroyed"` |

#### 7b. Health callback

After receiving `model.health.check`, the gateway must `POST` the result back to the `callback_url` provided in the event payload (which resolves to `/api/v1/ai_model_configs/:id/health_callback`) with `X-Gateway-Secret` authentication.

**Request body**
```json
{
  "health": {
    "health_status": "healthy",
    "health_latency_ms": 95,
    "error_message": null
  }
}
```

**Valid `health_status` values**: `healthy`, `degraded`, `unhealthy`, `unknown`

#### 7c. Style & Model Hub batch capabilities

Three new batch task capabilities are dispatched through the existing `ai_batch.dispatch` Redis event.  The gateway must implement handlers for:

| `capability` key | Gateway handler | Expected callback |
|---|---|---|
| `embedding.regenerate` | Regenerate dense float vectors for all `target_ids` using the **current default embedding model** (from `model.config.updated` state). Overwrites existing embeddings. | POST to `/api/v1/ai_batch_jobs/:id/progress` (same as existing batch flow) |
| `style.audit` | Analyse the visual style of each asset against the loaded style-preset library; return the top-matching preset slug and a confidence score. Write results as metadata tags on each asset via `PATCH /api/v1/assets/:uuid/metadata`. | POST to `/api/v1/ai_batch_jobs/:id/progress` after each batch; write style tags via asset metadata endpoint |
| `style.tag` | Same as `style.audit` but write only the single best-match preset slug as a `style_preset` tag without confidence scoring. | POST to `/api/v1/ai_batch_jobs/:id/progress` |

#### 7d. Style audit metadata write-back

When a `style.audit` or `style.tag` task completes for an asset, the gateway must `PATCH` the asset metadata with:

```json
{
  "metadata": {
    "tags": [
      { "type": "style_preset", "slug": "editorial-dark", "confidence": 0.87 }
    ]
  }
}
```

Endpoint: `PATCH /api/v1/assets/:uuid/metadata`  
Authentication: `X-Gateway-Secret` header  
On 404: skip silently (asset may have been deleted).

#### 7e. Style preset sync endpoint

In addition to the Redis `style.preset.sync` event, the gateway **should** expose an HTTP endpoint that allows the DAM to push presets directly (used as a fallback when Redis is unavailable):

```
POST /api/style_presets
```

**Request**
```json
{
  "slug": "editorial-dark",
  "name": "Editorial Dark",
  "description": "High-contrast editorial style",
  "active": true,
  "is_default": false,
  "style_params": {
    "tone": "editorial",
    "palette": ["#1a1a1a", "#ffffff"],
    "aspect_ratio": "16:9",
    "keywords": ["stark", "high-contrast", "monochrome"]
  }
}
```

**Response `200 OK`**
```json
{ "ref": "gw-preset-abc123" }
```

The `ref` value is stored as `gateway_ref` on the `StylePreset` record.

#### 7f. Acceptance criteria

- [ ] `model.config.updated` hot-swaps the routing table; subsequent embedding calls use the new default.
- [ ] `model.health.check` runs a ping and POSTs `health_status` + `health_latency_ms` to the DAM callback within 10 seconds.
- [ ] `style.preset.sync` upserts the preset into the gateway style library; stale cache is invalidated.
- [ ] `style.preset.changed` with `action == "destroyed"` removes the preset from the gateway registry.
- [ ] `embedding.regenerate` batch: vectors are written back via the embedding endpoint; `progress` endpoint receives live counters.
- [ ] `style.audit` batch: style tags are written to each asset's metadata via `PATCH /api/v1/assets/:uuid/metadata`.
- [ ] `style.tag` batch: single best-match slug tag written per asset.
- [ ] `POST /api/style_presets` accepts the style-params schema and returns `{ "ref": "..." }`.
- [ ] Health check response time < 15 s (including provider round-trip); gateway does not block other requests during health checks.


