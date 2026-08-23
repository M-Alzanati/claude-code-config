# Working effectively with a coding agent

Ordered by leverage.

## 1. Give the agent a way to check itself
Put the real commands in the project's `CLAUDE.md` — `pnpm test`, `cargo check`,
`ruff check .` — not "run tests." An agent that can verify self-corrects; one
that can't ships confident wrong code.

## 2. The agent never commits — you review first
No auto-commits, no `git commit` as a side effect of finishing a task, no
pushing. The agent stages nothing and leaves the working tree for you to read.
Review the diff yourself, then commit it yourself. A commit you did not read is
a change you did not make.

## 3. Never accept "done" without evidence
Ask for the command output, the failing-test-now-passing. Agents are most
confident in exactly the cases where they didn't actually look.

## 4. Reproduce before fixing
Make it write the failing test first. Converts "fix the bug" — unverifiable —
into a loop it can close without you.

## 5. Keep diffs small and scoped
Quality degrades on sprawling multi-file changes: the agent loses track of what
it already decided. Plan mode for anything crossing three files.

## 6. Push search into subagents
Fan-out exploration burns context on dead ends. Let a subagent read forty files
and return only the answer.

## 7. Watch context composition, not just size
400k of relevant code beats 80k of stale tool output and failed branches.
Compact at task boundaries, where accumulated context has least value.

---
The meta-practice: treat it as a fast junior that never tires and never says
"I'm not sure." Your job is supplying the verification it cannot supply itself.
