#!/bin/sh
# Validate this config. Called by install.sh and by the pre-commit hook.
# Exits non-zero if anything is broken. Run standalone any time: ./check.sh
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
cd "$CFG" || exit 1
fail=0
chk() { if [ "$1" = 0 ]; then printf '  ok    %s\n' "$2"; else printf '  FAIL  %s\n' "$2"; fail=1; fi; }

jq -e . settings.json >/dev/null 2>&1; chk $? "settings.json is valid JSON"
jq -e '.hooks' settings.json >/dev/null 2>&1; chk $? "hooks block present"

# Every hook command points at a script that exists.
# Read from a file, not a pipe: a `while` loop in a pipeline runs in a subshell
# where `fail=1` is discarded, so a missing hook would still exit 0.
tmp=$(mktemp)
jq -r '.hooks | to_entries[] | .value[] | .hooks[] | .command' settings.json 2>/dev/null |
    sed 's/^node //' | awk '{print $1}' > "$tmp"
while IFS= read -r c; do
    # Hook paths are written as ~/.claude/... but the config may live elsewhere
    # (CLAUDE_CONFIG_DIR, or a CI checkout), so resolve them against $CFG.
    p=$(printf '%s' "$c" | sed "s|^~/\.claude|$CFG|; s|^~|$HOME|")
    [ -f "$p" ]; chk $? "hook exists: $c"
done < "$tmp"
rm -f "$tmp"

# rtk-rewrite.sh rewrites every Bash command, so verify it has not been altered.
if [ -f hooks/.rtk-hook.sha256 ]; then
    ( cd hooks && sha256sum -c --status .rtk-hook.sha256 ) 2>/dev/null
    chk $? "rtk-rewrite.sh matches its recorded checksum"
fi

echo '{}' | ./statusline.sh >/dev/null 2>&1; chk $? "statusline.sh runs"
echo '{"cwd":"/"}' | ./hooks/suggest-claude-md.sh >/dev/null 2>&1; chk $? "suggest-claude-md.sh runs"

# The ignore rules that keep credentials and transcripts out must still hold.
for p in .credentials.json projects history.jsonl plugins settings.local.json; do
    git check-ignore -q "$p" 2>/dev/null; chk $? "gitignored: $p"
done

# No key material in anything git would track.
hits=$(git add -An --dry-run 2>/dev/null | sed "s/^add '//;s/'$//" | while IFS= read -r f; do
    grep -lEI 'sk-ant-[A-Za-z0-9]|ghp_[A-Za-z0-9]{20}|BEGIN [A-Z ]*PRIVATE KEY|AKIA[0-9A-Z]{16}' "$f" 2>/dev/null
done)
[ -z "$hits" ]; chk $? "no secrets in tracked files${hits:+ -> $hits}"

[ "$fail" = 0 ] && echo "all checks passed" || echo "CHECKS FAILED"
exit $fail
