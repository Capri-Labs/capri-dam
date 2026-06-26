# Changelog

All notable changes to Capri DAM are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Root-level project documentation: `CODE_OF_CONDUCT.md`, `RELEASING.md`,
  `CLAUDE.md`, `AGENTS.md`, `SECURITY.md`, `CHANGELOG.md`.
- `.editorconfig` and `.pre-commit-config.yaml` for consistent formatting and
  local quality gates.
- GitHub issue/PR templates and `CODEOWNERS`.

### Changed
- `README.md` rewritten to match the current `Makefile`, `Gemfile`, and
  `package.json` (Rails 8.1, MUI v9, Node 22.16.0, full make-target reference).
- `ARCHITECTURE.md` reduced to a pointer to the arc42 set in `docs/architecture/`.
- `CONTRIBUTING.md` rewritten; MUI references updated from v6 to **v9**.
- `LICENSE` changed from MIT to **Apache 2.0**.
- `.node-version` bumped to `22.16.0`.

### Fixed
- `PATCH /profile/preferences` no longer rejects the default timezone value.
  Timezone is now treated as a server-managed field and removed from the public
  profile API surface (model validation, permitted params, serializer, GraphQL
  type). Existing `'UTC'` rows are normalised to the IANA-canonical `'Etc/UTC'`.

[Unreleased]: https://github.com/your-org/headless-dam/compare/main...HEAD

