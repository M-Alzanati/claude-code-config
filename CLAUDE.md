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

- Default to 1-3 sentences. Answer first, stop there.
- No section headers, no bold labels, no summary of what you just did unless asked.
  If the tool output already shows it, don't restate it.
- Expand only when asked for a report, review, or explanation — then be thorough.
- One caveat maximum. Pick the one that changes my decision; drop the rest.
- Use tables for comparisons
- Show file paths as `path/file.ts:line` for easy navigation
- Flag security concerns immediately

@RTK.md
