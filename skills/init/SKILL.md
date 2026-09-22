---
name: skein-init
description: Set a repository up for skein (parallel agents, one gate, any number of coordinators). Runs `skein init`, then interviews the user for the project rules the scaffold cannot detect (money, data, infrastructure, frozen paths, invariants, e2e), fills AGENTS.md and .skein/config.json, and commits. Use when asked to "set this repo up for skein", "add the swarm setup", or "make this repo multi-agent".
---

# /skein-init

You are setting a repository up so several agents, under any number of coordinators, can
build it in parallel with one merge gate. The mechanical part is a command; the judgment
part is a short interview. Do both.

## 1. Scaffold
```bash
~/.claude/skills/skein/bin/skein init            # add --name, --prefix, --board, --driver, --base if the defaults look wrong
```
Read what it printed: package manager, standard commands, board, driver. If it detected no
standard commands, stop and tell the user: until typecheck/lint/test scripts exist, the gate
cannot judge work, and the first task must be a harness task (see step 4).

## 2. Interview, grounded in the code
Read the repo first (package manifests, top-level layout, any existing AGENTS.md or
CLAUDE.md, CI, env examples). Then ask, 3 to 5 questions at a time, only what you could not
infer:
1. **Money and irreversible actions.** Payments, transactions, deploys, emails, publishes.
   Which commands or paths must a worker never run or touch?
2. **Secrets and data.** Which env vars are live credentials a worker must never hold? These
   become `ENV_WITHHOLD` in `.superset/setup.sh`. Any personal data rules?
3. **Frozen paths.** The contract: types, schemas, generated code, deployed artifacts. These
   go in `coordinatorOwned` in the plan.
4. **Invariants the gate should enforce.** Patterns that must never appear in added lines
   outside specific files (a flag read only through one module, a forbidden API). These
   become `invariants` in `.skein/config.json`.
5. **Heavier verification.** A smoke or e2e suite the gate should run before merge, and what
   it needs (a server, a port range, a database). Becomes `e2e`.
6. **Caps.** How many agents this repo can absorb at once (`maxAgents`), given review
   throughput.

## 3. Write it down
- Fill `## Project rules` in `AGENTS.md` with numbered rules in the same voice as the rest
  of the file: concrete, with the reason, no filler.
- Set `invariants`, `monotonic`, `e2e`, `maxAgents`, `coordinatorOwned` additions and any
  `secretPatterns`/`secretAllow` in `.skein/config.json` and `docs/plan/wps.json`.
- Set `ENV_WITHHOLD` and any `PREPARE` steps in `.superset/setup.sh`.
- Add project-specific hygiene to the end of `docs/plan/COORDINATOR.md` only if it is a real
  pitfall you know of, not a generic warning.

## 4. First task
If the repo has no usable test harness, write the first task now: `<PREFIX>-00` "test
harness and CI", owning the config files and a `tests/` directory, whose brief makes the
gate able to judge work. Use `/skein-brief` for it. Otherwise ask what the first wave should
be and hand off to `/skein-brief`.

## 5. Prove it and commit
```bash
skein doctor && skein plan
git add -A && git commit -m "chore: skein setup (gate, plan, worker rules)"
```
Push (with `<PREFIX>_COORDINATOR=1` if the hook is active) or open a PR, whichever the
repo's rules say. Report in a few lines: what was detected, what the interview added, what
the first task is.
