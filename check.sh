#!/bin/sh
# Validate this config. Called by install.sh and by the pre-commit hook.
# Exits non-zero if anything is broken. Run standalone any time: ./check.sh
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
cd "$CFG" || exit 1
fail=0
chk() { if [ "$1" = 0 ]; then printf '  ok    %s\n' "$2"; else printf '  FAIL  %s\n' "$2"; fail=1; fi; }

jq -e . settings.json >/dev/null 2>&1; chk $? "settings.json is valid JSON"
jq -e '.hooks' settings.json >/dev/null 2>&1; chk $? "hooks block present"

# Every hook and statusline command uses the portable config expression and
# points at a script that exists.
# Read from a file, not a pipe: a `while` loop in a pipeline runs in a subshell
# where `fail=1` is discarded, so a missing hook would still exit 0.
tmp=$(mktemp -d)
if [ $? -ne 0 ] || [ -z "$tmp" ]; then
    chk 1 "hook commands extracted"
elif jq -r '(.hooks | to_entries[] | .value[] | .hooks[] | .command), .statusLine.command' settings.json 2>/dev/null > "$tmp/raw" &&
     sed 's/^node //' "$tmp/raw" > "$tmp/stripped" &&
     awk 'NF == 1 { print; next } { exit 1 }' "$tmp/stripped" > "$tmp/commands"; then
    chk 0 "hook commands extracted"
    while IFS= read -r path; do
        prefix='${CLAUDE_CONFIG_DIR:-$HOME/.claude}/'
        case "$path" in
            \""$prefix"*\")
                relative=${path#\""$prefix"}
                relative=${relative%\"}
                chk 0 "portable config path: $path"
                case "$relative" in
                    ''|/*|*[!A-Za-z0-9._/-]*|.|./*|*/./*|*/.|..|../*|*/../*|*/..)
                        chk 1 "safe config path: $path"
                        ;;
                    *)
                        chk 0 "safe config path: $path"
                        [ -f "$CFG/$relative" ]; chk $? "command exists: $path"
                        ;;
                esac
                ;;
            *) chk 1 "portable config path: $path" ;;
        esac
    done < "$tmp/commands"
else
    chk 1 "hook commands extracted"
fi
if [ -n "$tmp" ]; then
    rm -f "$tmp/raw" "$tmp/stripped" "$tmp/commands"
    rmdir "$tmp" 2>/dev/null
fi

# rtk-rewrite.sh rewrites every Bash command, so verify it has not been altered.
if [ -f hooks/.rtk-hook.sha256 ]; then
    if command -v sha256sum >/dev/null 2>&1; then
        ( cd hooks && sha256sum -c --status .rtk-hook.sha256 ) 2>/dev/null
    elif command -v shasum >/dev/null 2>&1; then
        ( cd hooks && shasum -a 256 -c .rtk-hook.sha256 >/dev/null ) 2>/dev/null
    else
        false
    fi
    chk $? "rtk-rewrite.sh matches its recorded checksum"
fi

echo '{}' | ./statusline.sh >/dev/null 2>&1; chk $? "statusline.sh runs"
echo '{"cwd":"/"}' | ./hooks/suggest-claude-md.sh >/dev/null 2>&1; chk $? "suggest-claude-md.sh runs"

# The ignore rules that keep credentials and transcripts out must still hold.
for p in .credentials.json projects history.jsonl plugins settings.local.json; do
    git check-ignore -q "$p" 2>/dev/null; chk $? "gitignored: $p"
done

# Scan exactly what the next commit would contain. `git grep --cached` covers
# both committed entries and normally staged changes without changing the index.
hits=$(git grep --cached -lE 'sk-ant-[A-Za-z0-9]|github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|BEGIN [A-Z ]*PRIVATE KEY|A[KS]IA[0-9A-Z]{16}' -- 2>/dev/null)
scan_status=$?
case "$scan_status" in
    0) chk 1 "no secrets in Git index -> $hits" ;;
    1) chk 0 "no secrets in Git index" ;;
    *) chk 1 "Git index secret scan completed" ;;
esac

[ "$fail" = 0 ] && echo "all checks passed" || echo "CHECKS FAILED"
exit $fail
