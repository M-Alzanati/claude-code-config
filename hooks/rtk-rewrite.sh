#!/usr/bin/env bash
# rtk-hook-version: 2
# RTK Claude Code hook — rewrites commands to use rtk for token savings.
# Requires: rtk >= 0.23.0, jq
#
# This is a thin delegating hook: all rewrite logic lives in `rtk rewrite`,
# which is the single source of truth (src/discover/registry.rs).
# To add or change rewrite rules, edit the Rust registry — not this file.

if ! command -v jq &>/dev/null; then
  exit 0
fi

if ! command -v rtk &>/dev/null; then
  exit 0
fi

# Version guard: rtk rewrite was added in 0.23.0.
# Older binaries: warn once and exit cleanly (no silent failure).
RTK_VERSION=$(rtk --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
if [ -n "$RTK_VERSION" ]; then
  MAJOR=$(echo "$RTK_VERSION" | cut -d. -f1)
  MINOR=$(echo "$RTK_VERSION" | cut -d. -f2)
  # Require >= 0.23.0
  if [ "$MAJOR" -eq 0 ] && [ "$MINOR" -lt 23 ]; then
    echo "[rtk] WARNING: rtk $RTK_VERSION is too old (need >= 0.23.0). Upgrade: cargo install rtk" >&2
    exit 0
  fi
fi

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [ -z "$CMD" ]; then
  exit 0
fi

# Local deviation from the "all logic lives in rtk rewrite" rule above: rtk
# translates these shapes into commands it then rejects, so a working call
# becomes an error the caller has to notice and retry. Skipping is cheaper.
#   cat a b     -> rtk read a b     (rtk read accepts a single file)
#   tail -3 f   -> rtk read -3 f    (numeric shorthand is not an rtk flag)
#   find -exec  -> rtk find -exec   (rtk find has no -exec/-not/-prune)
# Drop a rule here once the corresponding rtk registry entry handles the shape.
skip_rewrite() {
  local cmd=$1 w n=0
  if [[ $cmd == find\ * ]]; then
    [[ $cmd == *" -exec "* || $cmd == *" -not "* || $cmd == *" -prune "* ]] && return 0
  fi
  [[ $cmd =~ ^(head|tail)[[:space:]]+-[0-9] ]] && return 0
  if [[ $cmd == cat\ * ]]; then
    local -a words
    read -ra words <<<"$cmd"
    for w in "${words[@]:1}"; do [[ $w == -* ]] || n=$((n + 1)); done
    [ "$n" -gt 1 ] && return 0
  fi
  return 1
}

if skip_rewrite "$CMD"; then
  exit 0
fi

# Delegate all remaining rewrite logic to the Rust binary.
# rtk rewrite exits 1 when there's no rewrite — hook passes through silently.
REWRITTEN=$(rtk rewrite "$CMD" 2>/dev/null) || exit 0

# No change — nothing to do.
if [ "$CMD" = "$REWRITTEN" ]; then
  exit 0
fi

# Anything that is not an rtk invocation is not a rewrite we understand.
if [[ $REWRITTEN != rtk\ * ]]; then
  exit 0
fi

ORIGINAL_INPUT=$(echo "$INPUT" | jq -c '.tool_input')
UPDATED_INPUT=$(echo "$ORIGINAL_INPUT" | jq --arg cmd "$REWRITTEN" '.command = $cmd')

jq -n \
  --argjson updated "$UPDATED_INPUT" \
  '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "updatedInput": $updated
    }
  }'
