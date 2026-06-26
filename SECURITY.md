# Security Policy

## Supported versions

Security fixes are provided for the latest released minor version. Older
versions may receive critical fixes at the maintainers' discretion.

| Version | Supported |
|---------|-----------|
| latest `MINOR` | ✅ |
| previous `MINOR` | ⚠️ critical fixes only |
| older | ❌ |

## Reporting a vulnerability

**Please do not report security vulnerabilities through public GitHub issues,
discussions, or pull requests.**

Instead, use one of the following private channels:

- Email **security@capri-dam.dev** with a description of the issue.
- Or use GitHub's [private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability)
  feature for this repository.

Please include, where possible:

- A description of the vulnerability and its impact.
- Steps to reproduce (proof-of-concept, affected endpoint, payload).
- Affected version(s) / commit SHA.
- Any suggested remediation.

## Our commitment

- We aim to **acknowledge** your report within **48 hours**.
- We will provide a **remediation timeline** after triage, typically targeting a
  fix within **90 days** depending on severity and complexity.
- We will keep you informed of progress and credit you in the release notes
  (unless you prefer to remain anonymous).

## Scope

In scope:

- The Rails application (REST `/api/v1/**`, GraphQL `/graphql`, web UI).
- Authentication / authorization (Devise, Doorkeeper, Keycloak SSO).
- Background workers and data handling (Sidekiq, ActiveStorage).

Out of scope:

- Vulnerabilities in third-party dependencies already tracked upstream — report
  those to the upstream project (we monitor CVEs via `bundler-audit` and
  Dependabot).
- Findings that require physical access or a compromised developer machine.

## Dependency security

Dependencies are continuously monitored:

- `bundle exec bundler-audit check --update` (Ruby gem CVEs)
- Dependabot weekly updates (`.github/dependabot.yml`)
- Explicit CVE version floors are pinned in the `Gemfile` — **do not weaken
  them**.

