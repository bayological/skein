---
name: skein-gate
description: Run the skein merge gate for a task and explain any failure with the fix. Use when asked to "gate TASK-03", "run the gate", "why did the gate fail", or before merging.
---

# /skein-gate

```bash
skein gate <ID>                      # full: static checks, standard, e2e, accept
skein gate <ID> --only boundary,secrets,test-integrity,invariants   # fast static pass
```
Run it from the task's worktree (the worker's, or a review worktree), never from a dirty
checkout: `clean-tree` fails on uncommitted changes by design.

Interpret the result for the user, one line per failed check with the smallest fix:
- `boundary`: a file outside the task's `owned` globs. Either the brief was wrong (fix the
  plan, coordinator PR) or the worker drifted (ask it to revert).
- `secrets`: rotate first, then remove from history; do not just delete the line.
- `test-integrity`: a skipped or focused test, or a shared suite that shrank. Never merge.
- `invariants`: a repo rule from `.skein/config.json`; the message says which.
- `standard`/`e2e`/`accept`: read the command output above the summary.
Never suggest weakening the gate, an invariant, or a test to get green.
