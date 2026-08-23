# Claude Output Accuracy Design

## Goal

Keep Claude Code responses brief while preventing unsupported status claims.

## Design

The existing SessionStart and UserPromptSubmit hooks remain the single source
of output guidance. Add one explicit evidence rule to both: Claude may say
work is complete, fixed, passing, secure, or ready to commit only when the
current response includes fresh command output proving that claim; otherwise
it must say the state is unverified. Keep the existing one-to-three-sentence
default and expansion only when requested.

## Verification

Extend the shell regression suite to invoke both hooks and assert that their
JSON `additionalContext` contains the concise-response and evidence rules.
