# Releasing Capri DAM

This document describes how a maintainer cuts and ships a release of Capri DAM.
Only repository maintainers with push access to `main` and the container registry
can perform a release.

---

## Table of contents

- [Versioning policy](#versioning-policy)
- [Release cadence](#release-cadence)
- [Pre-release checklist](#pre-release-checklist)
- [Cutting a release](#cutting-a-release)
- [Building and publishing the Docker image](#building-and-publishing-the-docker-image)
- [Deploying with Kamal](#deploying-with-kamal)
- [Post-release verification](#post-release-verification)
- [Hotfix releases](#hotfix-releases)
- [Rolling back](#rolling-back)

---

## Versioning policy

Capri DAM follows [Semantic Versioning 2.0.0](https://semver.org/):

```
MAJOR.MINOR.PATCH   e.g. 2.4.1
```

| Bump | When |
|------|------|
| **MAJOR** | Breaking API/schema changes, removed endpoints, incompatible migrations |
| **MINOR** | Backwards-compatible features, new endpoints, additive migrations |
| **PATCH** | Bug fixes, security patches, doc-only or dependency bumps |

Release tags are prefixed with `v` (e.g. `v2.4.1`).

---

## Release cadence

- **Minor** releases ship roughly every 2–4 weeks from `main`.
- **Patch** releases ship on demand for bug or security fixes.
- **Security** fixes are released as soon as a fix is verified (see
  [`CONTRIBUTING.md`](CONTRIBUTING.md#security-disclosures)).

---

## Pre-release checklist

Before tagging, confirm that **all** CI gates are green on the target commit:

| Gate | Command |
|------|---------|
| RuboCop | `bundle exec rubocop` |
| Brakeman | `bundle exec brakeman -q` |
| Bundler audit | `bundle exec bundler-audit check --update` |
| Backend specs | `make test` |
| Frontend unit | `yarn test --ci` |
| System tests | `bundle exec rspec spec/system/` |
| Playwright E2E | `yarn playwright test` |
| Docker build | `docker build .` |
| API docs current | `make check-api-specs && make check-graphql-docs` |

Also verify:

- [ ] `db/schema.rb` is committed and matches the latest migration.
- [ ] All new endpoints have Swagger annotations and regenerated docs
      (`make api-docs`).
- [ ] `CHANGELOG.md` has an entry for this version (see below).
- [ ] Any new environment variables / credentials are documented and present in
      the deployment target.

---

## Cutting a release

1. **Update the changelog.** Move entries from the `Unreleased` section into a
   new dated version heading:

   ```markdown
   ## [2.4.1] - 2026-06-26
   ### Fixed
   - Profile preferences no longer reject the default timezone value.
   ```

2. **Bump the version.** Update the version constant / file used by the build
   (e.g. `config/application.rb` or a `VERSION` file) if present.

3. **Open a release PR** titled `chore(release): v2.4.1`, get it reviewed, and
   squash-merge into `main`.

4. **Tag the merge commit:**

   ```bash
   git checkout main
   git pull origin main
   git tag -a v2.4.1 -m "Release v2.4.1"
   git push origin v2.4.1
   ```

5. **Create the GitHub Release** from the tag, pasting the changelog section as
   the release notes. Tagging triggers the release workflow.

---

## Building and publishing the Docker image

The production image is built from the repository [`Dockerfile`](Dockerfile).
CI builds and pushes on tag, but to build manually:

```bash
# Build, tagging with both the version and `latest`
docker build \
  --build-arg RUBY_VERSION=$(cat .ruby-version) \
  --build-arg NODE_VERSION=$(cat .node-version) \
  -t ghcr.io/your-org/capri-dam:v2.4.1 \
  -t ghcr.io/your-org/capri-dam:latest \
  .

# Push
docker push ghcr.io/your-org/capri-dam:v2.4.1
docker push ghcr.io/your-org/capri-dam:latest
```

> Never tag a non-`main`, untested commit as `latest`.

---

## Deploying with Kamal

Capri DAM deploys via [Kamal](https://kamal-deploy.org/). Ensure
`RAILS_MASTER_KEY` and registry credentials are present in your environment.

```bash
# Deploy the freshly pushed image to all roles
bin/kamal deploy

# Run migrations as part of (or before) the deploy
bin/kamal app exec 'bin/rails db:migrate'

# Tail logs to confirm a clean boot
bin/kamal app logs -f
```

For zero-downtime migrations, ship additive schema changes first, deploy, then
ship the code that depends on them in the following release.

---

## Post-release verification

After the deploy settles:

1. Hit the health endpoint — `GET /up` should return `200`.
2. Smoke-test a core flow (login → upload asset → search).
3. Confirm Sidekiq workers are processing (`/sidekiq` dashboard).
4. Watch error tracking / OpenTelemetry traces for new exceptions.
5. Verify the API docs render at `/api/rest` and `/api/graphql`.

---

## Hotfix releases

For an urgent fix against a published release:

```bash
# Branch from the release tag, not main
git checkout -b fix/critical-xyz v2.4.1

# Make the minimal fix + test, then open a PR into main
# After merge, tag a new PATCH version
git tag -a v2.4.2 -m "Hotfix v2.4.2"
git push origin v2.4.2
```

Cherry-pick the fix back to any still-supported release branches if applicable.

---

## Rolling back

If a release is bad, roll the deployment back to the previous image:

```bash
# Re-deploy the last known-good version
bin/kamal rollback
# or pin explicitly:
bin/kamal deploy --version v2.4.0
```

If a migration must be reversed, run its `down` step deliberately and document
the data implications — **never** auto-rollback destructive migrations without
review.

