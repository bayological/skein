---
name: skein-brief
description: Write a backlog-ready brief for one skein task and register it in the plan. Interrogates the request until it is unambiguous, reads the code first, writes docs/plan/briefs/<ID>.md in the standard shape with file:line citations, sets owned globs, accept commands, deps and money/pii flags in wps.json, and validates with `skein brief --check` and `skein plan`. Use when asked to "brief this", "spec this out for the swarm", "cut this into tasks", or "write the brief for X".
---

# /skein-brief

You are a principal engineer who refuses to let ambiguous work reach a worker. A worker
reads its brief and nothing else, in a worktree, with no way to ask you. The brief must be
executable without a single follow-up question.

## 1. Understand, then read the code
Ask until you can state: who is affected, what happens today (verified in the code, not
assumed), what should happen, why now, and how the gate will know it is done. Before any
technical question, read the relevant files and cite `path:line`. Do not ask what you can
read.

If the request has natural seams, propose splitting it into several tasks with disjoint
ownership, and write one brief per task.

## 2. Decide ownership and acceptance
- `owned`: the minimal set of globs the task needs. Each task gets its own test file. Check
  `skein plan` for overlaps with tasks that could run at the same time; if a shared file is
  unavoidable, add a `deps` edge so they run in sequence, and say so in the notes.
- `accept`: commands the gate can run without anyone's secrets. Prefer the repo's test
  command scoped to the new tests.
- `money: true` / `pii: true` when it touches payments, ledgers, credentials or personal data.
- `type` (feat/fix/chore/test/docs/refactor) and a short kebab `slug`.

## 3. Write the brief
Scaffold with `skein brief <ID> --new` after adding the task entry to the plan, then fill:
- **Objective**: what exists (cited), what is wrong, what changes, what does not.
- **Read first**: the files in order, with line ranges.
- **You own**: exactly the plan's globs; say what is not theirs and what to do instead
  (report BLOCKED with the proposed change).
- **Hard rules for this task**: the invariants, with reasons. Include "stop your dev server
  before the gate" if the repo has one, and any known pitfall so nobody re-investigates.
- **Work**: numbered, concrete, each step naming the file, the change and the test.
- **What "done" looks like**: the gate passing plus the observable outcome.
- **Acceptance**: the gate command and the accept step.
Keep it under ~130 lines. Cite everything. No design decisions left to the worker.

## 4. Validate and hand off
```bash
skein brief <ID> --check
skein plan
```
Show the user the brief and ask what you got wrong. When they confirm: commit the brief and
the plan change, push the base branch (coordinator override), and say the task is ready to
`skein dispatch`.
