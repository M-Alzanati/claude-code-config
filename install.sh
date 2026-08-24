#!/bin/sh
# Deploy this checkout into ~/.claude. Clone anywhere; the checkout stays the
# source of truth and ~/.claude gets symlinks back to it.
#
#   git clone <url> ~/src/claude-code-config
#   cd ~/src/claude-code-config && ./install.sh
#
#   ./install.sh --update     # git pull, relink anything new, verify
#
# Managed paths are symlinked, so a plain `git pull` already updates them.
# settings.json is copied instead: Claude Code rewrites it itself (/output-style,
# plugin install) and an atomic write would replace a symlink with a real file.
#
# Flags:  --update   pull before deploying
#         --yes      accept every prompt
#         --dry-run  print actions, change nothing
#         --no-deps  config only, skip dependency install
set -e

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

# $0 may itself be reached through a symlink; walk to the real checkout.
resolve_dir() {
    p=$1
    while [ -L "$p" ]; do
        t=$(readlink "$p")
        case "$t" in
            /*) p=$t ;;
            *) p=$(dirname "$p")/$t ;;
        esac
    done
    (cd "$(dirname "$p")" && pwd)
}

SRC=$(resolve_dir "$0")
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
YES=0; DRY=0; DEPS=1; UPDATE=0
for a in "$@"; do
    case "$a" in
        --yes|-y) YES=1 ;;
        --dry-run) DRY=1 ;;
        --no-deps) DEPS=0 ;;
        --update) UPDATE=1 ;;
        *) say "unknown flag: $a"; exit 2 ;;
    esac
done

for c in jq git; do
    command -v "$c" >/dev/null || { say "FATAL: $c is required"; exit 1; }
done

if [ "$SRC" = "$CFG" ]; then
    say "FATAL: this checkout is $CFG itself."
    say "  Earlier versions made ~/.claude the repository. Clone it elsewhere:"
    say "    git clone <url> ~/src/claude-code-config"
    say "    cd ~/src/claude-code-config && ./install.sh"
    exit 1
fi

say "source: $SRC"
say "target: $CFG"

# ---------- 1. update ----------
if [ "$UPDATE" = 1 ]; then
    git -C "$SRC" rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1 || {
        say "FATAL: $SRC has no upstream branch; nothing to pull."
        exit 1
    }
    run git -C "$SRC" pull --ff-only
fi

# ---------- 2. deploy ----------
# Everything Claude Code only ever reads is symlinked, so `git pull` is enough.
LINKS="CLAUDE.md RTK.md PRACTICES.md statusline.sh check.sh hooks output-styles templates skills/ui-styling"

STAMP=$(date +%Y%m%d-%H%M%S)
BAK="$CFG/backups/preinstall-$STAMP"

backup() {
    # Only displaced real files are kept; a correct symlink never gets here.
    [ -e "$1" ] || [ -L "$1" ] || return 0
    rel=${1#"$CFG"/}
    if [ "$DRY" = 1 ]; then say "  would back up: $rel -> $BAK/$rel"; return 0; fi
    mkdir -p "$BAK/$(dirname "$rel")"
    mv "$1" "$BAK/$rel"
    say "  saved $rel -> $BAK/$rel"
}

link() {
    target="$SRC/$1"
    dest="$CFG/$1"
    [ -e "$target" ] || { say "  skip $1 (not in checkout)"; return 0; }
    if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$target" ]; then
        say "  ok   $1"
        return 0
    fi
    backup "$dest"
    run mkdir -p "$(dirname "$dest")"
    run ln -s "$target" "$dest"
    say "  link $1"
}

run mkdir -p "$CFG"
for rel in $LINKS; do link "$rel"; done

# The legacy in-place layout checked the whole repository out into $CFG. These
# paths are repository infrastructure, never configuration Claude Code reads,
# so a migrated install would keep serving stale copies of them forever.
LEGACY=".github .githooks .gitignore LICENSE README.md install.sh"
for rel in $LEGACY; do
    [ -L "$CFG/$rel" ] && continue
    [ -e "$CFG/$rel" ] || continue
    backup "$CFG/$rel"
done

if [ "$DRY" = 1 ]; then
    say "  would write settings.json"
elif [ -f "$CFG/settings.json" ] && [ ! -L "$CFG/settings.json" ]; then
    # Repo wins on shared keys; machine-local keys survive. `.hooks` is taken
    # from the repo verbatim rather than deep-merged: `*` can add and override
    # but never delete, so a hook event dropped upstream would otherwise linger
    # here forever, still pointing at a script that no longer exists.
    mkdir -p "$BAK"
    cp "$CFG/settings.json" "$BAK/settings.json"
    jq -s '. as [$local, $repo] | ($local * $repo) | .hooks = $repo.hooks' \
        "$BAK/settings.json" "$SRC/settings.json" > "$CFG/.settings.merged"
    mv "$CFG/.settings.merged" "$CFG/settings.json"
    say "  merge settings.json (repo wins on conflicts, local extras kept)"
else
    backup "$CFG/settings.json"
    cp "$SRC/settings.json" "$CFG/settings.json"
    say "  copy settings.json"
fi

if [ -d "$CFG/.git" ]; then
    say "NOTE: $CFG is still a git repository from the old in-place layout."
    say "  Its tracked files are shadowed by the symlinks above. Once you are"
    say "  satisfied this install works:  rm -rf $CFG/.git"
fi

[ "$DEPS" = 0 ] && { say "--no-deps: skipping dependencies"; DEPS_DONE=1; }

# ---------- 3. system packages ----------
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

    # ---------- 4. plugins (driven by settings.json, not a hardcoded list) ----------
    if command -v claude >/dev/null; then
        jq -r '.enabledPlugins | to_entries[] | select(.value == true) | .key' "$CFG/settings.json" |
        while IFS= read -r id; do
            mkt=${id#*@}
            claude plugin list 2>/dev/null | grep -q "$id" && { say "plugin ok: $id"; continue; }
            repo=$(jq -r --arg m "$mkt" '.extraKnownMarketplaces[$m].source.repo // empty' "$CFG/settings.json")
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

    # ---------- 5. rtk ----------
    # Deliberately not auto-installed: the binary carries no source URL, and
    # RTK.md warns that a different project publishes the same command name.
    # Installing the wrong `rtk` would silently break every Bash call.
    command -v rtk >/dev/null || \
        say "WARN: rtk missing, hooks/rtk-rewrite.sh will not rewrite. Install it
     yourself, then re-run. Verify with: rtk gain   (must not error)"
fi

# ---------- 6. verify ----------
# .git/config is not versioned, so the pre-commit hook must be wired here.
run git -C "$SRC" config core.hooksPath .githooks
say "--- verify ---"
if [ "$DRY" = 0 ]; then
    chmod +x "$SRC/statusline.sh" "$SRC/check.sh" "$SRC"/hooks/*.sh "$SRC"/.githooks/* 2>/dev/null || true
    CLAUDE_CONFIG_DIR="$CFG" "$SRC/check.sh" || { say "  (config has problems, see above)"; exit 1; }
fi
say "done. restart Claude Code to load hooks."
