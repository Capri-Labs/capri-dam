# Architecture

The full, versioned architecture documentation for Capri DAM is maintained as
an **arc42** document set under [`docs/architecture/`](docs/architecture/).

## Quick-start reading order

| Document | What it covers |
|----------|---------------|
| [`01_introduction_and_goals.adoc`](docs/architecture/src/01_introduction_and_goals.adoc) | Purpose, quality goals, stakeholders |
| [`02_constraints.adoc`](docs/architecture/src/02_constraints.adoc) | Technical and organisational constraints |
| [`03_scope_and_context.adoc`](docs/architecture/src/03_scope_and_context.adoc) | System boundaries, external interfaces |
| [`04_solution_strategy.adoc`](docs/architecture/src/04_solution_strategy.adoc) | Key architectural decisions |
| [`05_building_block_view.adoc`](docs/architecture/src/05_building_block_view.adoc) | Component decomposition (PlantUML diagrams) |
| [`06_runtime_view.adoc`](docs/architecture/src/06_runtime_view.adoc) | Key runtime scenarios (asset upload, search …) |
| [`07_deployment_view.adoc`](docs/architecture/src/07_deployment_view.adoc) | Infrastructure topology, CDN, Sidekiq |
| [`08_concepts.adoc`](docs/architecture/src/08_concepts.adoc) | Cross-cutting concepts (RBAC, audit, i18n …) |
| [`09_design_decisions.adoc`](docs/architecture/src/09_design_decisions.adoc) | ADRs — what we decided and why |
| [`10_quality_scenarios.adoc`](docs/architecture/src/10_quality_scenarios.adoc) | Quality attribute scenarios |
| [`11_technical_risks.adoc`](docs/architecture/src/11_technical_risks.adoc) | Known risks and mitigation |
| [`12_glossary.adoc`](docs/architecture/src/12_glossary.adoc) | Domain and technical terms |

## Building the docs locally

```bash
# Install tools (once)
sudo gem install asciidoctor asciidoctor-pdf asciidoctor-diagram \
  asciidoctor-diagram-plantuml rouge --no-document

# Render HTML
asciidoctor -r asciidoctor-diagram \
  -a imagesdir=images \
  docs/architecture/index.adoc \
  -D docs/architecture/out/html

# Render PDF
asciidoctor-pdf -r asciidoctor-diagram \
  -a pdf-theme=docs/architecture/theme/arc42-theme.yml \
  -a imagesdir=images \
  docs/architecture/index.adoc \
  -o docs/architecture/out/capri-dam-architecture.pdf
```

Or trigger the **Build HTML + PDF docs** GitHub Actions workflow which publishes
the artefacts to GitHub Pages automatically.

## High-level summary

Capri DAM follows a **Hybrid Monolith** pattern:

```
Browser
  │
  ├─ Rails router → HTML shell  (Hotwire / Turbo for light interactions)
  │                 └─ React islands  (mounted via data-view registry)
  │
  ├─ REST API     /api/v1/**   (asset operations, search, folders)
  └─ GraphQL API  /graphql     (admin queries, reporting, DAM graph)

Background
  └─ Sidekiq workers
       ├─ ingest/     (adapter pull: AEM, Bynder, S3, …)
       ├─ metadata/   (AI tagging, EXIF extraction, vector embeddings)
       ├─ reports/    (async PDF/XLSX generation)
       └─ mailers/    (notifications, workflow alerts)

Storage
  ├─ PostgreSQL  — RBAC, metadata, audit logs, folder policies
  ├─ pgvector    — semantic similarity search on asset embeddings
  ├─ Redis       — Sidekiq queues, caching, Action Cable
  └─ ActiveStorage (local disk ↔ S3 / GCS / Azure Blob + CDN)
```

For deeper reading, start with
[`docs/architecture/src/04_solution_strategy.adoc`](docs/architecture/src/04_solution_strategy.adoc).
