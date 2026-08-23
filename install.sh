#!/bin/sh
# Install this config onto a machine. Safe to re-run; never clobbers.
#
#   cd ~/.claude && git init && git remote add origin <url> && git fetch origin
#   git checkout origin/main -- install.sh && sh install.sh
#
# Use this instead of `git reset --hard`, which would destroy existing config.
#
# Flags:  --yes  accept every prompt   --dry-run  print actions, change nothing
#         --no-deps  config only, skip dependency install
set -e
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
BRANCH=origin/main
YES=0; DRY=0; DEPS=1
for a in "$@"; do
    case "$a" in
        --yes|-y) YES=1 ;;
        --dry-run) DRY=1 ;;
        --no-deps) DEPS=0 ;;
        origin/*|*/*) BRANCH="$a" ;;
    esac
done
cd "$CFG"

say() { printf '%s\n' "$*"; }
run() { if [ "$DRY" = 1 ]; then say "  would run: $*"; else "$@"; fi; }
ask() {
    [ "$YES" = 1 ] && return 0
    [ "$DRY" = 1 ] && return 0
    [ -t 0 ] || return 1                      # non-interactive: skip, don't hang
    printf '  %s [y/N] ' "$1"
    read -r r </dev/tty || return 1
    case "$r" in [yY]*) return 0 ;; *) return 1 ;; esac
}

for c in jq git; do
    command -v "$c" >/dev/null || { say "FATAL: $c is required"; exit 1; }
done

# ---------- 1. config ----------
STAMP=$(date +%Y%m%d-%H%M%S)
BAK="$CFG/backups/preinstall-$STAMP"
if [ "$DRY" = 0 ]; then
    mkdir -p "$BAK"
    for f in settings.json settings.local.json CLAUDE.md statusline.sh; do
        [ -f "$f" ] && cp "$f" "$BAK/"
    done
fi
say "backed up existing config -> $BAK"

run git checkout "$BRANCH" -- .

if [ "$DRY" = 0 ] && [ -f "$BAK/settings.json" ]; then
    # repo wins on shared keys; machine-local keys survive.
    # (jq '*' replaces arrays wholesale, so the repo's hook set wins outright.)
    jq -s '.[0] * .[1]' "$BAK/settings.json" settings.json > .settings.merged
    mv .settings.merged settings.json
    say "merged settings.json (repo wins on conflicts, local extras kept)"
fi

[ "$DEPS" = 0 ] && { say "--no-deps: skipping dependencies"; DEPS_DONE=1; }

# ---------- 2. system packages ----------
if [ "${DEPS_DONE:-0}" = 0 ]; then
    for pm in paru yay pacman apt dnf brew; do command -v $pm >/dev/null && { PM=$pm; break; }; done
    for dep in node; do
        command -v "$dep" >/dev/null && continue
        say "$dep is missing (hooks/ecc/* need it)"
        [ -z "$PM" ] && { say "  no known package manager; install $dep manually"; continue; }
        case "$PM" in
            pacman) pkg="nodejs"; cmd="sudo pacman -S --needed $pkg" ;;
            paru|yay) pkg="nodejs"; cmd="$PM -S --needed $pkg" ;;
            apt) pkg="nodejs"; cmd="sudo apt install -y $pkg" ;;
            dnf) pkg="nodejs"; cmd="sudo dnf install -y $pkg" ;;
            brew) pkg="node"; cmd="brew install $pkg" ;;
        esac
        ask "install $pkg via $PM?" && run sh -c "$cmd" || say "  skipped"
    done

    # ---------- 3. plugins (driven by settings.json, not a hardcoded list) ----------
    if command -v claude >/dev/null; then
        jq -r '.enabledPlugins | to_entries[] | select(.value == true) | .key' settings.json |
        while IFS= read -r id; do
            mkt=${id#*@}
            claude plugin list 2>/dev/null | grep -q "$id" && { say "plugin ok: $id"; continue; }
            repo=$(jq -r --arg m "$mkt" '.extraKnownMarketplaces[$m].source.repo // empty' settings.json)
            say "plugin missing: $id"
            if ask "install $id?"; then
                [ -n "$repo" ] && { run claude plugin marketplace add "$repo" || say "  marketplace add failed"; }
                run claude plugin install "$id" || say "  install failed: $id (continuing)"
            else
                say "  skipped"
            fi
        done
    else
        say "WARN: 'claude' CLI not on PATH, cannot auto-install plugins"
    fi

    # ---------- 4. rtk ----------
    # Deliberately not auto-installed: the binary carries no source URL, and
    # RTK.md warns that a different project publishes the same command name.
    # Installing the wrong `rtk` would silently break every Bash call.
    command -v rtk >/dev/null || \
        say "WARN: rtk missing, hooks/rtk-rewrite.sh will not rewrite. Install it
     yourself, then re-run. Verify with: rtk gain   (must not error)"
fi

# ---------- 5. verify ----------
# .git/config is not versioned, so the pre-commit hook must be wired here.
run git config core.hooksPath .githooks
say "--- verify ---"
if [ "$DRY" = 0 ]; then
    chmod +x statusline.sh check.sh hooks/*.sh .githooks/* 2>/dev/null || true
    ./check.sh || { say "  (config has problems, see above)"; exit 1; }
fi
say "done. restart Claude Code to load hooks."
