# Claude Code config

[![check](https://github.com/M-Alzanati/claude-code-config/actions/workflows/check.yml/badge.svg)](https://github.com/M-Alzanati/claude-code-config/actions/workflows/check.yml)

One versioned Claude Code setup for a new machine: settings, hooks, output
style, statusline, and a small set of shared instructions. Clone it anywhere;
the installer deploys it into `~/.claude`.

## Install

Clone this repository anywhere you keep source, then run the installer. It
deploys into `~/.claude` — the checkout stays the source of truth.

```sh
git clone https://github.com/M-Alzanati/claude-code-config.git ~/src/claude-code-config
cd ~/src/claude-code-config
./install.sh
```

Restart Claude Code when the installer finishes.

The installer needs `git` and `jq`. It backs up anything it displaces, keeps
machine-local settings, installs optional dependencies only with confirmation,
and runs the validation check before it succeeds. Re-running it is safe.

Useful flags:

```sh
./install.sh --update    # git pull, relink anything new, verify
./install.sh --dry-run   # show what would change
./install.sh --no-deps   # skip dependency installation
./install.sh --yes       # accept installer prompts
```

## Update

```sh
cd ~/src/claude-code-config
./install.sh --update
```

Managed paths are symlinked into `~/.claude`, so a plain `git pull` already
updates the hooks, output styles, templates and instruction files. Use
`--update` when you want the pull, the relink for newly added paths, the
`settings.json` merge, and the validation check in one step.

`settings.json` is the exception: it is copied rather than symlinked, because
Claude Code rewrites it itself (`/output-style`, plugin installs) and an atomic
write would silently replace a symlink with a regular file. Your keys survive
the merge; the repository wins on shared ones.

Four blocks are repository-managed and replaced outright rather than merged:
`hooks`, `statusLine`, `enabledPlugins` and `extraKnownMarketplaces`. Merging
can add and override but never delete, so anything you drop upstream would
otherwise live on in every existing install. The practical consequence: declare
a plugin in this repository's `settings.json`, not with `claude plugin install`,
or the next update will remove it again. Everything else — `env`, `model`,
`theme`, your own keys — still merges.

## How it is laid out

| Path in `~/.claude` | Kind | Source |
| --- | --- | --- |
| `hooks/` | symlink | checkout |
| `output-styles/` | symlink | checkout |
| `templates/` | symlink | checkout |
| `skills/ui-styling` | symlink | checkout |
| `statusline.sh`, `check.sh` | symlink | checkout |
| `CLAUDE.md`, `RTK.md`, `PRACTICES.md` | symlink | checkout |
| `settings.json` | copy | merged on install |
| `settings.local.json` | untouched | yours |

Deleting the checkout breaks the symlinks, so keep it somewhere permanent.

`~/.claude` holds only live configuration. Repository infrastructure —
`README.md`, `LICENSE`, `install.sh`, `.gitignore`, `.github/`, `.githooks/` —
is swept into `backups/` if an earlier in-place install left copies there.

## Verify

```sh
cd ~/src/claude-code-config
./check.sh
```

It checks the JSON, hook paths, script startup, the configured output style,
ignored sensitive files, the RTK hook checksum, and token-like material in the
Git index. Config checks run against `~/.claude`; the ignore rules and secret
scan run against the checkout. It also runs from `.githooks/pre-commit`, so a
broken `settings.json` cannot be committed.

Two further suites run in CI on Linux and macOS, and are worth running by hand
before a change to the installer or the hooks:

```sh
sh tests/check-security.sh   # secret scanning, path safety, installer behaviour
python -m pytest skills/ui-styling/scripts/tests
```

`tests/check-security.sh` takes several minutes: it builds throwaway git
repositories and config directories for each case rather than mocking them.

## What this config changes

- `settings.json` enables the hooks, statusline, model preferences, and plugins.
- `output-styles/codex.md` is the active output style: Codex CLI's final-answer
  rules — plain text, short `**Title Case**` headers only when they aid
  scanning, `-` bullets, monospace for commands and paths, and clickable
  `path/file.ts:42` references. Switch with `/output-style`.
- `hooks/ecc/` stores bounded, project-specific session metadata and suggests
  compaction when tool use grows large.
- `statusline.sh` shows the current project and context usage.
- `CLAUDE.md` and `PRACTICES.md` contain the shared working rules.

`CLAUDE.md` also sets the voice for pull requests, review comments and commit
messages, on the theory that they are read by a person months later:

- Say why, not what — the diff already shows what changed.
- Open with the point. No "This PR...", no "Summary:", no restating the title.
- Skip the compliments; "Great work!" and "Nice catch!" are padding.
- One concern per review comment, with the concrete failure it causes. Ask
  rather than assert when you are not sure it is wrong.
- Suggest the fix. A complaint without a direction is work handed back.
- Plain words: no emoji headers, no severity badges, no checklists where two
  sentences do.

Set `CLAUDE_CONFIG_DIR` to deploy somewhere other than `~/.claude`; the
installer, hooks and validator all honor it.

## Before you rely on it

- Read `CLAUDE.md` and `PRACTICES.md`; they are preferences, not universal rules.
- `rtk` is optional. Without it the Bash hook no-ops; `RTK.md` says so at the
  top, and a fork that does not use rtk should drop the `@RTK.md` import from
  `CLAUDE.md`. Verify the binary you install is the intended tool — a different
  project publishes the same command name.
- `hooks/rtk-rewrite.sh` skips a few command shapes rtk mistranslates into
  commands it then rejects (`cat` with several files, `head`/`tail -N`, `find`
  with `-exec`). Remove a guard once the matching rtk registry entry is fixed.
- The vendored `hooks/ecc/` code does not update itself. Update it deliberately.
- Earlier versions made `~/.claude` itself the repository. If yours still has a
  `~/.claude/.git`, the installer says so; remove it once the new install works.
  Files that layout left behind are swept into `backups/` on the next install,
  so `~/.claude/README.md` and `~/.claude/install.sh` no longer exist — read
  them in the checkout, which is the only copy that tracks the current state.

## License

MIT. `hooks/ecc/` is MIT code from
[affaan-m/everything-claude-code](https://github.com/affaan-m/everything-claude-code).
`skills/ui-styling/` is Apache-2.0; its license is included with the skill.
