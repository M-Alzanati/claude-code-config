#!/bin/sh
# SessionStart: if a project has no CLAUDE.md, tell Claude to offer creating one.
# Gated to git repos so it stays quiet in $HOME and scratch dirs.
cwd=$(jq -r '.cwd // ""' 2>/dev/null)
[ -n "$cwd" ] && cd "$cwd" 2>/dev/null || exit 0
root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -f "$root/CLAUDE.md" ] && exit 0
[ -f "$root/.claude/no-claude-md" ] && exit 0

printf 'This project (%s) has no CLAUDE.md. Ask the user ONCE whether to create one from the template at %s/templates/CLAUDE.md, adapted to this project (its stack, test command, conventions). Do not ask twice in a session. If they decline, run: mkdir -p %s/.claude && touch %s/.claude/no-claude-md\n' \
  "$root" "$HOME/.claude" "$root" "$root"
