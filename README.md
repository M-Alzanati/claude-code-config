# Claude Code config

Global Claude Code configuration — settings, hooks, statusline, skills —
versioned so a new machine reproduces the setup.

## The idea

A rule written in prose gets ignored. A rule wired into a hook doesn't. Most of
what's here is some instruction that kept getting dropped, converted into
something mechanical:

- **The agent never commits — you review first.** In `PRACTICES.md`, and the
  reason the installer wires a pre-commit hook instead of trusting good intent.
- **The output contract is injected twice** — in full at session start, and as a
  short recall on *every* prompt. By mid-session the session-start copy is 100k
  tokens behind what you just typed, and instruction-following decays with
  distance. Restating it at close range is the fix.
- **The config validates itself.** `check.sh` runs on every commit through
  `.githooks/pre-commit`, so a broken `settings.json`, a hook pointing at a file
  that doesn't exist, or a credential in a tracked file can't land.
- **`.gitignore` is deny-by-default.** `~/.claude` holds OAuth tokens, every
  conversation transcript, and your prompt history. An allowlist means a file you
  forget stays untracked instead of leaking. That's backwards from normal
  dotfiles, deliberately.
- **The installer merges, never clobbers.** It backs up first, and the repo wins
  only on shared keys — machine-local settings survive. Safe to re-run.
- **The statusline reads the harness's own numbers,** not an estimate, so there's
  nothing to drift out of sync when context accounting changes.

None of this is clever. It's the difference between telling an agent what you
want and arranging things so the wrong outcome can't happen quietly.

## Install

Claude Code creates `~/.claude` on first run, so add the remote to the directory
that already exists rather than cloning over it:

    cd ~/.claude
    git init && git remote add origin https://github.com/M-Alzanati/claude-code-config.git
    git fetch origin
    git checkout origin/main -- install.sh && sh install.sh
    # then restart Claude Code

`install.sh` is fetched but not yet on disk, so it is checked out on its own.
The full checkout is the installer's job — it backs up your existing config
first, which is the whole point of not checking out before running it.

Needs `git` and `jq` already present. The installer backs up your current config,
checks out the repo's files, and *merges* `settings.json` instead of replacing it
— the repo wins on shared keys, anything machine-local survives. It asks before
installing each dependency, and runs `./check.sh` at the end. Re-running is safe.

Flags: `--yes` (accept everything), `--dry-run` (change nothing), `--no-deps`.

Never `git reset --hard` here — it deletes local config the repo doesn't track.

## What's here

| Path | What |
|---|---|
| `settings.json` | Model, effort, env, hooks, statusLine, enabled plugins |
| `CLAUDE.md` | Global instructions for every project (imports `RTK.md`) |
| `PRACTICES.md` | How to drive a coding agent. The agent never commits — you review first |
| `statusline.sh` | Shell prompt, ponytail mode, and context usage — see below |
| `templates/CLAUDE.md` | Seed template offered to projects that lack one |
| `install.sh` / `check.sh` | Setup, and validation you can run any time |
| `hooks/` | See below |
| `skills/ui-styling/` | The one skill vendored here (Apache-2.0, license included) |

## Hooks

| Hook | When | Does |
|---|---|---|
| `suggest-claude-md.sh` | session start | In a git repo with no `CLAUDE.md`, offers to create one from the template. Decline once and `<repo>/.claude/no-claude-md` silences it for good |
| `output-style.sh` | session start | States the terse output contract in full |
| `output-reminder.sh` | every prompt | Repeats a short version, because by mid-session the copy above is 100k tokens behind the prompt and adherence decays with distance |
| `rtk-rewrite.sh` | before Bash | Routes commands through the rtk proxy |
| `ecc/*` | various | Session summaries, compact suggestions |

Hook paths use `~/.claude/...`; Claude Code expands the tilde, so nothing needs
rewriting per machine.

## Dependencies

| Dep | Needed by | Installed for you? |
|---|---|---|
| `git`, `jq` | the installer, statusline | No — required up front |
| `node` | `hooks/ecc/*` | Yes, via your package manager |
| Plugins | ponytail statusline segment, skills | Yes, from `enabledPlugins` |
| `rtk` | `hooks/rtk-rewrite.sh` | No — see below |

Plugins come from `settings.json`, not a hardcoded list: add one to
`enabledPlugins` and the installer picks it up. Everything is optional — a
missing dependency degrades one feature, it does not break the setup.

## Validation

    ./check.sh

Confirms `settings.json` parses, every hook command points at a file that exists,
the scripts run, the sensitive paths are still ignored, and no key material sits
in a tracked file. It also runs on every commit through `.githooks/pre-commit`,
so a broken config can't be committed. `git commit --no-verify` bypasses it.

`.gitignore` is deny-by-default: `*`, then explicit `!` unignores. A file you
forget stays untracked instead of leaking. **Add new config to the allowlist
explicitly; never loosen the `*` rule.**

## Statusline

Real output from `statusline.sh` at each threshold — grey while there's room,
amber when it's filling, red when it's time to `/compact`:

```
[you@host myproject][PONYTAIL]  91k/1.0M  9%     grey
[you@host myproject][PONYTAIL] 180k/1.0M 18%     amber
[you@host myproject][PONYTAIL] 420k/1.0M 42%     red
```

The knobs are all in `statusline.sh`. Usage comes straight from the
`context_window` object the harness puts on stdin, so there's no estimate to
keep in sync.

| Knob | Current |
|---|---|
| Context window | Auto-detected |
| Amber | 150k tokens (or 40% on a smaller window) |
| Red | 300k tokens (or 60%) |
| Colors | 245 grey / 179 amber / 203 red |

## Known rough edges

Worth knowing before you rely on this:

- **`hooks/ecc/*` is vendored, not tracked upstream.** It comes from
  [affaan-m/everything-claude-code](https://github.com/affaan-m/everything-claude-code)
  (MIT, attributed in each file). Local copies only — upstream fixes will not
  reach you on their own.
- **The secret scanner isn't in this repo.** `.githooks/pre-commit` chains to
  whatever `core.hooksPath` pointed at globally, then runs `check.sh`. On a fresh
  machine there's nothing on the other end of that chain — you get `check.sh`
  only.
- **`rtk` you install yourself.** The binary carries no source URL and an
  unrelated project publishes the same command name; installing the wrong one
  would silently break every Bash call. Verify with `rtk gain`. Note it strips
  comments from `cat` output — use `rtk proxy cat` to read a file verbatim.
- **`CLAUDE.md` and `PRACTICES.md` are one person's preferences,** not a house
  style. Read them before adopting them.
- **Most skills are deliberately not in this repo.** Four sit in `~/.claude/skills`
  with no license or provenance recorded, so they are gitignored rather than
  redistributed. Bring your own; `.gitignore` shows where to allowlist them.
- **Only exercised on Arch (`pacman`).** The installer detects apt, dnf, and brew
  too, but those paths are untested.

## License

MIT — see `LICENSE`. Two exceptions, both third-party and kept under their own
terms: `hooks/ecc/*` is MIT from
[affaan-m/everything-claude-code](https://github.com/affaan-m/everything-claude-code),
and `skills/ui-styling/` is Apache-2.0 with its license file included.
