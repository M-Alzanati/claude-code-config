# Security and Reliability Hardening Design

## Goal

Close every issue from the 2026-08-23 repository review without removing the
RTK, session-summary, custom-config, installer, or UI helper workflows.

## Design

- RTK may rewrite `tool_input.command`, but it must not approve the result.
  Claude Code's normal permission policy remains authoritative.
- `check.sh` scans the Git index, because the index is what a commit records.
  Scanner errors fail closed instead of being reported as a clean scan.
- Session state is keyed by a stable hash of the canonical project root and
  repository lineage, so normal commits keep the same file while a replacement
  repository gets a new key. Raw
  user prompts are neither persisted nor replayed; only bounded operational
  metadata is loaded for the matching project.
- The shadcn wrapper accepts only an exact SemVer value from `package.json`:
  `MAJOR.MINOR.PATCH` with optional SemVer prerelease and build metadata. It
  rejects leading `v`, whitespace, leading-zero core numbers or numeric
  prerelease identifiers, ranges, aliases, URLs, paths, and tags, then uses the
  pinned fallback. Build identifiers may contain leading zeros as SemVer allows.
- Every runtime path derives from `CLAUDE_CONFIG_DIR`, falling back to
  `$HOME/.claude`. The validator checks that same expression.
- Installer verification failures propagate to the caller.
- Compact counters live under the user-owned Claude config directory, not a
  predictable shared `/tmp` path.
- Root integration tests cover configuration and hook behavior; existing Python
  tests run in CI with coverage enforcement.

## Error Handling

Security checks fail closed. Optional hooks continue to degrade safely when an
optional executable is absent. Session hooks keep their existing non-blocking
behavior, but never cross project boundaries.

## Testing

One portable shell integration test exercises the configuration, installer,
staged and committed secret-index states, scanner errors, RTK output,
custom-directory and default-directory runtime consumers, session isolation,
and counter-path contracts. Existing pytest tests gain focused SemVer cases. CI
runs both suites and measures `shadcn_add` plus `tailwind_config_gen`, enforcing
at least 80% Python coverage without counting tests.
