# Claude Output Accuracy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep Claude Code responses concise and prohibit unsupported status claims.

**Architecture:** The two existing hook scripts remain the behavior boundary.
Both inject the same evidence requirement, while the existing shell suite
verifies the emitted `additionalContext` rather than model behavior.

**Tech Stack:** POSIX shell, jq, existing shell regression harness.

---

### Task 1: Enforce evidence-based output claims

**Files:**
- Modify: `hooks/output-style.sh`
- Modify: `hooks/output-reminder.sh`
- Test: `tests/check-security.sh`

- [x] Add a failing shell assertion that both hooks emit the evidence rule.
- [x] Run `sh tests/check-security.sh` and confirm it fails on the missing rule.
- [x] Add the same concise evidence requirement to both hook contexts.
- [x] Run `sh tests/check-security.sh` and confirm every check passes.
- [x] Run `CLAUDE_CONFIG_DIR="$PWD" ./check.sh` and `git diff --check`.
- [ ] Commit with `fix: enforce evidence-based Claude output`.
