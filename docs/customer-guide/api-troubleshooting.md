# API Troubleshooting Guide

> **Headless DAM — Customer Guide**  
> Version: v1 API · Last updated: June 2026

This guide covers the most common issues encountered when integrating with the Capri DAM API, along with step-by-step resolution paths.

---

## Table of Contents

1. [Authentication & Token Issues](#1-authentication--token-issues)
2. [File Upload Failures](#2-file-upload-failures)
3. [Asset Stuck in `processing` or `pending`](#3-asset-stuck-in-processing-or-pending)
4. [CDN URLs Returning 404 or Stale Content](#4-cdn-urls-returning-404-or-stale-content)
5. [Search Returning No Results](#5-search-returning-no-results)
6. [Workflow Tasks Not Progressing](#6-workflow-tasks-not-progressing)
7. [Smart Collection / Semantic Search Not Working](#7-smart-collection--semantic-search-not-working)
8. [Migration Batch Stuck in `extracting` or `transforming`](#8-migration-batch-stuck-in-extracting-or-transforming)
9. [Webhook Signature Validation Failures](#9-webhook-signature-validation-failures)
10. [Image Processing (Watermark / Process Image) Errors](#10-image-processing-watermark--process-image-errors)
11. [Duplicate Detection Not Finding Known Duplicates](#11-duplicate-detection-not-finding-known-duplicates)
12. [Rate Limiting & 429 Errors](#12-rate-limiting--429-errors)
13. [General HTTP Error Reference](#13-general-http-error-reference)

---

## 1. Authentication & Token Issues

### Symptom
```
HTTP 401 Unauthorized
{"error": "The access token is invalid"}
```

### Causes & Fixes

**A. Expired OAuth token**

OAuth Bearer tokens expire. Obtain a fresh token:
```bash
curl -X POST https://your-dam.com/oauth/token \
  -d "grant_type=client_credentials" \
  -d "client_id=YOUR_CLIENT_ID" \
  -d "client_secret=YOUR_CLIENT_SECRET"
```
Use the returned `access_token` in your `Authorization: Bearer <token>` header.

**B. Token not included in the header**

Ensure you are sending:
```
Authorization: Bearer eyJhbGciOiJSUzI1NiJ9...
```
Not `Token`, `Basic`, or any other scheme.

**C. Scope mismatch**

Your OAuth application may not have been granted the required scopes. Contact your DAM administrator to review the application's permission set in the OAuth management panel.

**D. Using a session cookie on a machine-to-machine endpoint**

API endpoints (`/api/v1/...`) accept both session cookies (web UI) and Bearer tokens. Machine-to-machine integrations must always use a Bearer token — session cookies are not valid outside a browser session.

---

## 2. File Upload Failures

### Symptom
```
HTTP 422 Unprocessable Entity
{"error": "No file provided"}
```

### Causes & Fixes

**A. Wrong Content-Type**

Upload requests **must** use `multipart/form-data`, not `application/json`:
```bash
curl -X POST https://your-dam.com/api/v1/assets \
  -H "Authorization: Bearer <token>" \
  -F "file=@/path/to/image.jpg" \
  -F "title=My Image" \
  -F "folder_id=42"
```

**B. File attached under wrong field name**

The API expects the file under the `file` parameter (not `attachment`, `upload`, or `data`).

**C. File size exceeds server limit**

The default Puma/Nginx body size limit is typically 50 MB. For larger files, contact your administrator to adjust `client_max_body_size` in Nginx or `RAILS_MAX_THREADS`/upload size configuration.

**D. Network timeout on large files**

For files > 20 MB over slow connections, you may hit a gateway timeout. Use chunked upload if available or compress the file first.

---

## 3. Asset Stuck in `processing` or `pending`

### Symptom

`POST /api/v1/assets` returns `202` with `status: processing`, but polling `GET /api/v1/assets/{id}/versions` continues to show `status: pending` indefinitely.

### Causes & Fixes

**A. Sidekiq workers are not running**

The DAM processes uploads asynchronously. Check worker status:
- Open `/admin/queues` in your browser (admin login required)
- Verify the `AssetProcessorWorker` queue is active and not paused
- If workers show as stopped, contact your system administrator

**B. Job failed silently**

Open the Sidekiq dashboard → **Dead Jobs** tab. If the asset's job appears there:
1. Review the error message
2. Fix the underlying issue
3. Click **Retry** to re-process

**C. File missing from staging path**

If the physical file was not correctly staged to `tmp/uploads/`, the worker will fail. Check Rails logs:
```bash
grep "AssetProcessorWorker" log/production.log | tail -50
```

**D. Database `active_version_id` not set**

In rare race conditions, the asset record may exist but have `active_version_id: null`. Contact support with the asset ID for manual resolution.

---

## 4. CDN URLs Returning 404 or Stale Content

### Symptom

An asset URL previously worked but now returns `404`, or the CDN is serving an old version after an overwrite.

### Causes & Fixes

**A. Asset was soft-deleted**

If the asset was moved to the Recycle Bin, its CDN URL becomes invalid. Restore the asset:
```bash
POST /api/v1/assets/{id}/restore
```
Or recover it from the UI → **Recycle Bin**.

**B. CDN cache not purged after version update**

After overwriting a version or uploading a new file, the edge cache may still serve the previous version for up to the TTL period (typically 24 hours). Trigger an immediate purge:
```bash
# For a specific asset
POST /api/v1/assets/{id}/purge_cdn

# For an entire folder
POST /api/v1/folders/{id}/purge_cdn

# For a collection
POST /api/v1/collections/{slug}/purge_cdn
```

**C. CDN provider is not configured**

Go to **Settings → CDN** and verify that your provider (Fastly, Cloudflare, or Akamai) is marked as `active` and credentials are correct. Run a connection test via `POST /api/v1/system_connectors/test_connection`.

**D. Local development environment**

In development, there is no CDN. Use the local asset proxy instead:
```
GET /api/v1/assets/local/{uuid}
```

---

## 5. Search Returning No Results

### Symptom

`GET /api/v1/search?q=logo` returns `{"meta": {"total_found": 0}, "results": []}` even though assets clearly exist.

### Causes & Fixes

**A. Assets are still in `pending` status**

The search endpoint only returns assets with `status: ready`. Wait for background processing to complete (see [Section 3](#3-asset-stuck-in-processing-or-pending)).

**B. Query is too specific**

The search uses `ILIKE '%term%'` against title and `original_filename`. Try:
- Shorter, more generic terms
- Partial words (e.g. `logo` instead of `logo_final_v3_approved`)

**C. Mode filter is excluding results**

`?mode=images` (the default) only returns `image/*` content types. If you're searching for PDFs, videos, or documents:
```
GET /api/v1/search?q=brief&mode=files
```
Or omit `mode` entirely to search all content types.

**D. Assets are soft-deleted**

Assets in the Recycle Bin are excluded from search. Check the bin at `GET /api/v1/bin`.

**E. Custom metadata filter has no matches**

If you pass a custom filter like `?region=EMEA`, it runs an exact JSONB match (`properties->>'region' = 'EMEA'`). Verify the asset's stored metadata key and value exactly match (case-sensitive).

---

## 6. Workflow Tasks Not Progressing

### Symptom

An asset has been assigned to a workflow but the reviewer cannot see it, or the task shows `pending` after submission.

### Causes & Fixes

**A. Wrong user is logged in**

Workflow tasks are user-assigned. Only the assigned user can submit a decision. Verify the logged-in user matches the `user_name` shown in `GET /api/v1/assets/{id}/workflow_history`.

**B. WorkflowEngineWorker is not running**

Task submission fires `WorkflowEngineWorker` asynchronously. If Sidekiq is down, decisions are recorded but the workflow does not advance. Check the Sidekiq dashboard.

**C. Task is not in `pending` state**

```
HTTP 422 {"error": "Task is no longer pending"}
```
The task was already completed or canceled. Use the workflow history endpoint to see the current state and who last acted on it.

**D. Admin bulk-stop was triggered**

An admin may have stopped the workflow instance via `POST /api/v1/workflows/bulk_stop`. Check with your DAM administrator.

---

## 7. Smart Collection / Semantic Search Not Working

### Symptom

`POST /api/v1/copilot/search` returns `HTTP 500 {"error": "Failed to process semantic query."}` or smart collection simulation returns empty results.

### Causes & Fixes

**A. Python AI Gateway is not running**

The semantic search depends on a Python FastAPI service for embedding generation. Verify:
```bash
curl http://localhost:8000/api/embed_query \
  -H "Content-Type: application/json" \
  -d '{"text": "test"}'
```
If this fails, start the AI Gateway service (see your deployment runbook).

**B. Asset embeddings are not populated**

Even if the gateway is running, semantic search only finds assets that have been embedded. New assets are embedded asynchronously after upload. Run a manual backfill if needed by calling `PUT /api/v1/assets/{id}/embedding` for each asset.

**C. Similarity threshold is too high**

The default threshold is `0.80`. If you are getting no results, try `0.70` or lower in the simulation (`POST /api/v1/collections/simulate_rule`).

**D. pgvector extension is not installed**

Contact your database administrator to verify `CREATE EXTENSION vector;` has been run on the database.

---

## 8. Migration Batch Stuck in `extracting` or `transforming`

### Causes & Fixes

**A. ExtractionWorker or TDM Worker is not running**

Check the Sidekiq dashboard for dead jobs in the `extraction` or `migration` queues.

**B. Source system credentials are invalid**

If the extraction worker cannot authenticate to the source system, the batch will stall. Update connector credentials via `PATCH /api/v1/system_connectors/{id}` and retry.

**C. Source system is rate-limiting the extraction**

Lower the `rps_limit` and `concurrency_limit` on the connector to avoid hitting the provider's rate limits.

**D. Batch is in `failed` status**

If the batch failed, it cannot be restarted. Create a new batch via `POST /api/v1/ingestion_batches` or retry via the admin Sidekiq dashboard → Dead Jobs.

**E. Large batch taking longer than expected**

Batches with 10,000+ assets can take 30–90 minutes to complete extraction and TDM transformation. Monitor progress via `GET /api/v1/ingestion_batches/{id}?status=pending` — the pending item count should decrease over time.

---

## 9. Webhook Signature Validation Failures

### Symptom
```
HTTP 401 Unauthorized
```
Webhook events from your source system are being rejected.

### Causes & Fixes

**A. Wrong signature header**

The DAM accepts:
- `x-hub-signature-256` (GitHub, generic)
- `x-adobe-signature` (Adobe I/O)

Verify your source system is sending one of these headers (not `x-signature` or similar).

**B. Signing secret mismatch**

The HMAC-SHA256 signature must be computed using the `webhook_secret` stored in the `SystemConnector` record. If you regenerated the secret on the source system, update it in the DAM connector settings.

**C. Payload was modified in transit**

The signature is computed over the **raw request body**. If any middleware (e.g. a reverse proxy) modifies the body (e.g. pretty-printing JSON), the signature will not match. Ensure the body is forwarded byte-for-byte.

**D. Timing attack mitigation**

The DAM uses `ActiveSupport::SecurityUtils.secure_compare` for constant-time comparison. Ensure you are comparing the full signature string, not just a prefix.

---

## 10. Image Processing (Watermark / Process Image) Errors

### Symptom
```
HTTP 500 {"error": "Failed to generate secure proxy."}
HTTP 422 {"error": "Source file not found on disk."}
```

### Causes & Fixes

**A. Source file is missing from disk**

The image baking pipeline reads from `storage/dam/<path>` or `tmp/uploads/<path>`. If the file was deleted from disk manually or the staging cleanup ran prematurely:
1. Re-upload the asset to restore the physical file
2. The `storage_path` property in `GET /api/v1/assets/{id}/audit_trail` shows the expected path

**B. MiniMagick / ImageMagick is not installed**

```bash
which convert   # Should return a path like /usr/bin/convert
convert -version
```
If missing, install ImageMagick:
```bash
# macOS
brew install imagemagick

# Ubuntu/Debian
apt-get install imagemagick
```

**C. Asset is not an image**

Watermarking only works for `image/*` content types. The `process_image` endpoint also requires an image source. Check `properties.content_type` via the audit trail endpoint.

**D. Insufficient disk space in tmp/**

The baking pipeline writes to `tmp/`. Ensure sufficient disk space is available:
```bash
df -h tmp/
```

---

## 11. Duplicate Detection Not Finding Known Duplicates

### Symptom

`POST /api/v1/assets/check_hashes` returns `{"duplicates": {}}` but you believe the file already exists.

### Causes & Fixes

**A. Hash was computed differently**

The system stores `SHA-256` checksums in `properties.checksum_sha256`. Ensure your client is computing the hash over the **raw binary content** of the file — not a base64-encoded version or a partial hash.

**B. The original upload was processed before hash extraction**

If the original upload was made without hash computation (older assets), the `checksum_sha256` property may be `null` in the database. These assets will not be detected as duplicates.

**C. Hash is stored on the version, not the asset**

Hashes are stored in `AssetVersion.properties`, not on the parent `Asset`. Ensure you are looking at versions, not assets.

---

## 12. Rate Limiting & 429 Errors

### Symptom
```
HTTP 429 Too Many Requests
```

### Causes & Fixes

The API applies rate limits per OAuth client. Default limits:
- **Upload** (`POST /api/v1/assets`): 60 requests/minute
- **Search** (`GET /api/v1/search`): 120 requests/minute
- **General API**: 300 requests/minute

**Handling 429 in your client:**

1. Check the `Retry-After` response header for the wait duration
2. Implement exponential backoff:
   ```
   Wait = min(2^attempt * 100ms + random(0..100ms), 30s)
   ```
3. For bulk ingestion, use the `IngestionBatch` API instead of uploading files one-by-one

**Requesting higher limits:**

Contact your DAM administrator to increase rate limits for your OAuth application.

---

## 13. General HTTP Error Reference

| Code | Meaning | Common Cause |
|------|---------|--------------|
| `400` | Bad Request | Missing required parameter (e.g. `ids` for bulk operations) |
| `401` | Unauthorized | Missing, expired, or invalid Bearer token |
| `403` | Forbidden | User lacks permission for this resource or action |
| `404` | Not Found | Resource ID does not exist or has been hard-deleted |
| `422` | Unprocessable Entity | Validation failed or business rule violation |
| `429` | Too Many Requests | Rate limit exceeded — implement backoff and retry |
| `500` | Internal Server Error | Unexpected error — check Rails logs and contact support |
| `202` | Accepted | Request was received and queued for async processing |

---

## Getting More Help

- **Rails logs**: `log/production.log` — filter by asset UUID or request ID
- **Sidekiq dashboard**: `/admin/queues` (admin login required)
- **API documentation**: `/api-docs` (Swagger UI)
- **System status**: `GET /admin/system_status` (admin API)
- **Support**: Create an issue at [github.com/apelluru/headless-dam](https://github.com/apelluru/headless-dam)

