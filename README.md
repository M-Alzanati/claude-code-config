# Claude Code config

[![check](https://github.com/M-Alzanati/claude-code-config/actions/workflows/check.yml/badge.svg)](https://github.com/M-Alzanati/claude-code-config/actions/workflows/check.yml)

One versioned Claude Code setup for a new machine: settings, hooks, statusline,
and a small set of shared instructions.

## Install

Claude Code creates `~/.claude` on first run. Install into that directory so
your existing local configuration can be backed up and merged:

```sh
cd ~/.claude
git init
git remote add origin https://github.com/M-Alzanati/claude-code-config.git
git fetch origin
git checkout origin/main -- install.sh
sh install.sh
```

Restart Claude Code when the installer finishes.

The installer needs `git` and `jq`. It backs up the current config, keeps
machine-local settings, installs optional dependencies only with confirmation,
and runs the validation check before it succeeds.

Useful flags:

```sh
sh install.sh --dry-run   # show what would change
sh install.sh --no-deps   # skip dependency installation
sh install.sh --yes       # accept installer prompts
```

## Verify

Run this from the configuration directory:

```sh
./check.sh
```

It checks the JSON, hook paths, script startup, ignored sensitive files, the
RTK hook checksum, and token-like material in the Git index. The same checks
run in CI on Linux and macOS.

## What this config changes

- `settings.json` enables the hooks, statusline, model preferences, and plugins.
- `hooks/output-style.sh` and `hooks/output-reminder.sh` keep normal replies
  brief and require fresh command output before claiming work is complete,
  passing, secure, or ready to commit.
- `hooks/ecc/` stores bounded, project-specific session metadata and suggests
  compaction when tool use grows large.
- `statusline.sh` shows the current project and context usage.
- `CLAUDE.md` and `PRACTICES.md` contain the shared working rules.

Use `CLAUDE_CONFIG_DIR` instead of `~/.claude` when you deliberately keep this
configuration elsewhere; the hooks and validator honor it.

## Before you rely on it

- Read `CLAUDE.md` and `PRACTICES.md`; they are preferences, not universal rules.
- `rtk` is optional but needed for the Bash rewrite hook. Verify the binary you
  install is the intended tool before enabling it.
- The vendored `hooks/ecc/` code does not update itself. Update it deliberately.
- Do not run `git reset --hard` inside `~/.claude`; it can discard local config
  that this repository intentionally does not track.

## License

MIT. `hooks/ecc/` is MIT code from
[affaan-m/everything-claude-code](https://github.com/affaan-m/everything-claude-code).
`skills/ui-styling/` is Apache-2.0; its license is included with the skill.
