# skein

A skein is a flock of geese in flight. They fly in a V and rotate the lead as it tires, so
there is no fixed leader, only whoever is in front right now. skein runs a repo that way:
many coding agents in parallel, each in its own worktree, under any number of coordinators,
with one merge gate that decides what is done.

It packages the swarm setup that grew across several repos (a Superset workspace per task,
a coordinator that briefs and gates, workers that never merge) into a kit you install once
and vendor into each repo, the way gstack does.

## What you get

- **A gate.** `skein gate <ID>` checks a clean tree, path ownership, committed secrets, test
  integrity, your repo's own invariants, then your standard commands, an optional e2e suite,
  and the task's acceptance commands. The worker runs it before claiming done, the
  coordinator runs it before merging, CI runs it on every PR. Vendored and coordinator-owned,
  so a worker cannot weaken the gate it is judged by.
- **A plan.** `docs/plan/wps.json` is the task DAG: each task's `owned` globs, `deps`,
  `accept` commands, and money/pii flags. `skein plan` prints what is ready and which ready
  tasks overlap. Disjoint ownership is what makes parallelism safe.
- **A board.** Claims live on GitHub issues (default), Superset tasks, or nowhere for a solo
  run. Assigning yourself is the claim. Any number of coordinators, no fixed owner.
- **Two caps.** Your machine's (`~/.skein/config.json`) and the repo's (`.skein/config.json`),
  counted across all coordinators through the board. The smaller wins.
- **Drivers.** Superset (workspaces, agents, terminals through its CLI) or local (git
  worktrees plus Claude Code headless), behind one interface.
- **Commands and skills.** `skein init|upgrade|doctor|plan|brief|dispatch|watch|status|send|
  gate|review|merge`, and Claude Code skills that wrap the judgment parts: `/skein-init`,
  `/skein-brief`, `/skein-coordinate`, `/skein-gate`, `/skein-status`.

## Install

```bash
git clone https://github.com/bayological/skein ~/.claude/skills/skein
~/.claude/skills/skein/setup        # registers the skills, links ~/.local/bin/skein
```
Needs `git`, `node`, `jq`, `gh`. Superset's CLI for the Superset driver; `codex` for
cross-model reviews (falls back to Claude).

## Set a repo up

```bash
cd your-repo
skein init                          # or the /skein-init skill, which also interviews you
```
This writes `.skein/config.json`, vendors the runtime into `scripts/skein/`, and adds
`AGENTS.md`, `docs/plan/` (runbook, coordinator prompt, onboarding, the plan), a CI
workflow, a pre-push hook that refuses the base branch, and Superset lifecycle scripts.
Existing files are left alone. Fill in the project rules, commit, push.

Day to day nobody types these commands. You open a session in your checkout, paste
`docs/plan/COORDINATOR-PROMPT.md`, and talk. The coordinator runs the commands.

## How a task moves

```
/skein-brief  ->  docs/plan/briefs/<ID>.md + plan entry      (coordinator, with you)
skein dispatch    claim on the board, workspace, setup, worker launched
skein watch       the worker's completion envelope
skein gate        static checks, standard, e2e, accept        (worker, then coordinator)
skein review      cross-model review in a read-only worktree  (money/pii tasks)
skein merge       gate again, squash-merge, close the claim, delete the workspace
```

## Config

`.skein/config.json` (repo, committed):

| key | what |
|---|---|
| `name`, `prefix` | project name; task ids are `<prefix>-NN` |
| `board` | `{type: github\|superset\|none, repo}` |
| `driver` | `{type: superset\|local}` |
| `maxAgents` | repo cap, counted across coordinators |
| `install`, `standard`, `e2e` | commands the gate runs |
| `invariants` | `[{name, pattern, except, message}]`: added lines matching `pattern` outside `except` fail |
| `monotonic` | `[{file, pattern}]`: the count may never fall (shared suites only grow) |
| `secretPatterns`, `secretAllow` | extra key patterns; known dev keys to ignore |
| `worker`, `review` | model policy |
| `workerPrompt` | override the fixed worker prompt (`{ID}`, `{NAME}`, `{BRIEF}`, `{GATE}`) |

`~/.skein/config.json` (per machine): `{"maxAgents": 3}`, and optionally
`projects: {"<repo path>": {"supersetProjectId": "…"}}`. `SKEIN_MAX_AGENTS`,
`SKEIN_PROJECT_ID`, `SKEIN_DRIVER` override per shell.

## Principles

- **A worker's claim is not evidence.** The gate is, plus a human or a different model
  reading the diff.
- **Ownership is the lock.** Two tasks never own one file at the same time.
- **The board is the other lock.** Assigning yourself is the claim; an assigned task is not
  yours.
- **Everything is on disk or on the board.** A new coordinator resumes from the plan, the
  briefs, and `skein status`. Sessions end; the record does not.
- **Workers never merge, never poll GitHub, never run a skill.** Their gate is the gate.

## Upgrading

```bash
skein upgrade        # in a repo: pulls the kit, resyncs scripts/skein/, leaves config and plan alone
```

MIT.
