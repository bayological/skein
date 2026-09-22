---
name: skein-coordinate
description: Run a wave as the skein coordinator: check the machine, dispatch ready tasks under both caps, watch for envelopes, gate, review money/pii tasks, merge, and keep the plan true. Use when asked to "run the wave", "dispatch KEPT-01", "coordinate", "merge what's done", or when a session was started from docs/plan/COORDINATOR-PROMPT.md.
---

# /skein-coordinate

You are one coordinator among possibly several. You write no feature code. Every step is a
`skein` command; your judgment goes into what to dispatch, how to triage a review, and when
to stop. Read `docs/plan/COORDINATOR.md` once per session.

## Loop
1. `skein doctor` (once), then `skein status` and `skein plan`.
2. Pick ready tasks with no ownership overlap, within both caps shown by status. Prefer
   tasks without `money`/`pii` when review capacity is tight. Say which you will dispatch
   and why, then:
   ```bash
   skein dispatch <ID>          # one JSON line; keep workspace and terminal ids
   skein watch <ID> &           # background; or poll skein status
   ```
3. On `DONE`: in the worker's worktree run `skein gate <ID>`. Read the diff yourself for what
   the gate cannot see. For `money`/`pii`: `skein review <ID>`, triage each finding on its
   merits, post rulings on the PR, `skein send <ID> "<fix request>"`, watch, gate again.
4. `skein merge <ID>`. Then `skein plan` to see what became dispatchable.
5. On `BLOCKED`: read the envelope. If it needs a contract change, that is yours: branch, ADR,
   PR. If it needs the user, tag the workspace `needs-owner` and say so plainly.
6. End of session: `skein status`, one paragraph in the repo's session log if it has one,
   and a list of anything waiting on the user.

## Rules
- Never claim or merge a task another coordinator holds; the commands refuse, respect it.
- Never `pkill` by pattern. Never poll GitHub in a loop.
- A worker's DONE is a claim, not evidence. The gate and your reading of the diff are.
- Stop when out of ready tasks, out of caps, or when the user asks. Report what shipped,
  what is gating, what is blocked, and what needs them.
