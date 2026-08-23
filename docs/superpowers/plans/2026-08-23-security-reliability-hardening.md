# Security and Reliability Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close all eight repository-review findings with regression coverage.

**Architecture:** Keep the current shell, Node.js, and Python entry points. Add
one root integration test for cross-cutting configuration behavior and extend
the existing pytest suite for the Python-specific trust boundary.

**Tech Stack:** POSIX shell, Node.js built-ins, Python 3, pytest, GitHub Actions.

---

### Task 1: Root security regression harness

**Files:**
- Create: `tests/check-security.sh`
- Modify: `check.sh`, `hooks/rtk-rewrite.sh`, `settings.json`, `install.sh`

- [x] Write failing checks for staged and committed-secret detection, scanner
      errors failing closed, RTK output without approval, runtime config paths,
      and installer failure propagation.
- [x] Run `sh tests/check-security.sh`; confirm each regression fails for the
      intended reason.
- [x] Apply the smallest production changes.
- [x] Run `sh tests/check-security.sh`; expect all checks to pass.

### Task 2: Session isolation and safe storage

**Files:**
- Modify: `hooks/ecc/lib/utils.js`
- Modify: `hooks/ecc/session-start.js`
- Modify: `hooks/ecc/session-end.js`
- Modify: `hooks/ecc/pre-compact.js`
- Modify: `hooks/ecc/suggest-compact.js`
- Test: `tests/check-security.sh`

- [x] Add failing cross-project, raw-prompt, and counter-location checks.
- [x] Run the focused checks and observe the expected failures.
- [x] Key session filenames by canonical project hash, remove raw prompt
      persistence, filter loads by project, and move counters under config.
- [x] Run the focused checks and expect them to pass.

### Task 3: shadcn package-spec validation

**Files:**
- Modify: `skills/ui-styling/scripts/tests/test_shadcn_add.py`
- Modify: `skills/ui-styling/scripts/shadcn_add.py`

- [x] Add parameterized failing tests for aliases, paths, URLs, ranges, tags,
      partial versions, leading whitespace/`v`, malformed prereleases, and
      leading-zero numeric identifiers; cover valid exact prerelease/build forms.
- [x] Run the focused pytest selection and confirm failure.
- [x] Accept only exact semantic versions; otherwise use the pinned fallback.
- [x] Run the focused tests and expect them to pass.

### Task 4: CI and final verification

**Files:**
- Modify: `.github/workflows/check.yml`
- Modify: `statusline.sh`
- Modify: `hooks/suggest-claude-md.sh`
- Modify: `hooks/ecc/lib/utils.js`

- [x] Run root integration tests from CI.
- [x] Inventory and test every runtime config-path consumer: `settings.json`
      hook/statusline commands, `statusline.sh`, `hooks/suggest-claude-md.sh`, and
      `hooks/ecc/lib/utils.js`, for both the override and default fallback.
- [x] Update those consumers to derive paths from `CLAUDE_CONFIG_DIR`, falling
      back to `$HOME/.claude`.
- [x] Install `skills/ui-styling/scripts/tests/requirements.txt` and run the
      complete Python suite with `--cov=shadcn_add --cov=tailwind_config_gen
      --cov-report=term-missing --cov-fail-under=80`.
- [x] Run shell, Node, and Python syntax checks plus all tests locally.
- [x] Review `git diff --check`, the complete diff, and security-sensitive paths.
- [x] Request independent correctness and security reviews; address all high and
      important findings.
