#!/bin/sh
# Short recall of the output contract, injected on EVERY user prompt.
# SessionStart alone is not enough: by mid-session the full contract is 100k
# tokens behind the prompt and adherence decays. This keeps it adjacent.
# Deliberately terse — a long reminder every turn is both costly and ignored.
jq -n --arg c 'Output contract (active every response): answer first, 1-3 sentences, then stop.
No section headers, no bold labels, no summary of what you just did.
Report only: a failure, a skipped part, an assumption that changes the outcome,
an irreversible/outward-facing action, or a security concern. One caveat max.
Expand only if this prompt asked for a review, report, explanation, or plan.
Before sending: over 3 sentences without depth being asked for? Cut it.' \
  '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$c}}'
