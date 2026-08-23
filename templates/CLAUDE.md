# CLAUDE.md

Behavioral guidelines. Merge with project-specific instructions as needed.

**Tradeoff:** These bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them — don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

Reach for what already exists — this codebase, the standard library, a native
platform feature, an installed dependency — before writing anything new. Read
the task and the code it touches first; a small diff in the wrong place is a
second bug, not a simplification.

- No features beyond what was asked. No abstractions for single-use code.
- No "flexibility" or configurability that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

**The test:** would a senior engineer say this is overcomplicated?

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it — don't delete it.
- Remove imports/variables/functions that YOUR changes made unused.

**The test:** every changed line should trace directly to the request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:

```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
```

Strong criteria let you loop independently. Weak criteria ("make it work")
require constant clarification.

Non-trivial logic leaves ONE runnable check behind — the smallest thing that
fails if the logic breaks. No frameworks, no fixtures unless asked.

---

Source: [Karpathy guidelines](https://github.com/multica-ai/andrej-karpathy-skills) (MIT).
The laziness mechanics (the ladder, root-cause-over-symptom, what never to
simplify away) live in the ponytail plugin — deliberately not repeated here.
