# Global Preferences

## Workflow

- Explain reasoning before making changes
- Use plan mode for complex multi-file changes
- Never auto-commit unless explicitly asked
- Never add `Co-Authored-By: Claude` or any generated-by trailer to a commit
  message or PR body. My name is the only one on my commits.
- When unsure between approaches, ask first
- Run tests after code changes

## Code Style

- Prefer `type` over `interface`
- Prefer named exports over default exports
- Use strict equality (`===`)
- Use template literals over string concatenation
- Keep functions small and focused

## Communication

Reply formatting lives in the active output style (`output-styles/codex.md`),
not here — that file owns headers, bullets and length. These are the
preferences it does not cover:

- Answer first. Depth on request is fine; unrequested depth is not.
- Don't restate what the tool output or the diff already shows.
- One caveat maximum. Pick the one that changes my decision; drop the rest.
- Use tables for comparisons.
- Flag security concerns immediately, before the rest of the answer.
- Never call work done, passing, fixed or secure without fresh command output
  from this turn. Say it is unverified instead.

## Pull requests, reviews and commit messages

Written for a person who will read them months from now, in a normal
colleague's voice.

- Say why, not what. The diff already shows what changed; the prose exists to
  explain the reason it had to.
- Open with the point. No "This PR...", no "Summary:", no restating the title.
- Skip the compliments. "Great work!", "Nice catch!" and similar padding say
  nothing and read as filler.
- One concern per review comment, with the concrete failure it causes. If you
  are not sure it is wrong, ask about it instead of asserting it.
- Suggest the fix when you have one. A complaint without a direction is work
  handed back rather than help offered.
- Plain words over ceremony: no emoji headers, no severity badges, no
  bullet-point checklists where two sentences do.
- Never write in a register you would not use out loud to the author.

@RTK.md
