#!/bin/sh
# Claude Code statusLine: [user@host cwd][PONYTAIL] 222k/1.0M 22%
# The harness sends context_window ready-made — no transcript parsing needed.
input=$(cat)
cwd=$(printf '%s' "$input" | jq -r '.cwd // ""')

printf '[%s@%s %s]' "$(whoami)" "$(hostname -s)" "$(basename "${cwd:-$PWD}")"

# Prefer the installed plugin (newest) over the marketplace checkout.
P="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins"
# BSD sort has no -V; newest installed plugin is the useful portable fallback.
pt=$(ls -td "$P/cache/ponytail/ponytail/"*/hooks/ponytail-statusline.sh 2>/dev/null | head -1)
[ -f "$pt" ] || pt="$P/marketplaces/ponytail/hooks/ponytail-statusline.sh"
[ -f "$pt" ] && sh "$pt" 2>/dev/null

set -- $(printf '%s' "$input" | jq -r '
    .context_window | select(.) |
    "\(.total_input_tokens // 0) \(.context_window_size // 0) \(.used_percentage // 0)"' 2>/dev/null)
used=$1 limit=$2 pct=$3
[ -n "$used" ] && [ "${limit:-0}" -gt 0 ] || exit 0

# Absolute thresholds; clamped so they still fire on smaller windows.
amber=150000; [ $((limit * 40 / 100)) -lt "$amber" ] && amber=$((limit * 40 / 100))
red=300000;   [ $((limit * 60 / 100)) -lt "$red" ]   && red=$((limit * 60 / 100))
if   [ "$used" -ge "$red" ];   then c=203   # red: compact now
elif [ "$used" -ge "$amber" ]; then c=179   # amber: getting full
else                                c=245   # grey: fine
fi

if [ "$limit" -ge 1000000 ]; then
    lim=$(printf '%d.%dM' $((limit / 1000000)) $((limit % 1000000 / 100000)))
else
    lim="$((limit / 1000))k"
fi
printf ' \033[38;5;%sm%dk/%s %d%%\033[0m' "$c" "$((used / 1000))" "$lim" "$pct"
